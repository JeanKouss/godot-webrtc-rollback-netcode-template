extends Node

# ---------------------------------------------------------------------------
# OnlineMatch — Global singleton for Nakama + WebRTC multiplayer
#
# Required by NakamaWebRTCNetworkAdaptor (hardcoded to /root/OnlineMatch).
# Stack: Nakama auth → socket → match → WebRTC peer mesh → SyncManager
#
# Usage:
#   await OnlineMatch.connect_to_nakama("127.0.0.1", 7350, "defaultkey")
#   await OnlineMatch.create_match()   # host
#   await OnlineMatch.join_match(id)   # clients
#   # listen to match_ready(players) then start the game
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# WebRTC signaling op codes (sent over Nakama match data)
# ---------------------------------------------------------------------------
const OP_WEBRTC_OFFER        := 2
const OP_WEBRTC_ANSWER       := 3
const OP_WEBRTC_ICE_CANDIDATE := 4

# ---------------------------------------------------------------------------
# Player representation
# ---------------------------------------------------------------------------
class Player:
    var session_id : String
    var peer_id    : int
    var username   : String
    var presence           ## NakamaRTAPI.UserPresence — stored for unicast signaling

    func _init(p_session_id: String, p_peer_id: int, p_username: String = "", p_presence = null) -> void:
        session_id = p_session_id
        peer_id    = p_peer_id
        username   = p_username
        presence   = p_presence

# ---------------------------------------------------------------------------
# Signals — required by NakamaWebRTCNetworkAdaptor
# ---------------------------------------------------------------------------
signal webrtc_peer_added(webrtc_peer, player)
signal webrtc_peer_removed(webrtc_peer, player)
signal disconnected()
signal match_left()

# ---------------------------------------------------------------------------
# Signals — game / UI events
# ---------------------------------------------------------------------------
signal error(message)
signal connected_to_nakama()
signal match_created(match_id)
signal match_joined(match_id)
signal player_joined(player)
signal player_left(player)
signal match_ready(players)
signal match_not_ready()

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------
var _nakama_client   : NakamaClient  = null
var _nakama_session  : NakamaSession = null
var _nakama_socket   : NakamaSocket  = null

var _match_id        : String = ""
var _my_session_id   : String = ""

## session_id → Player
var _players         : Dictionary = {}

## session_id → WebRTCPeerConnection
var _webrtc_peers    : Dictionary = {}

## session_id → Array of {mid, index, sdp} — ICE candidates buffered until remote SDP is set
var _pending_ice_candidates : Dictionary = {}

## WebRTCMultiplayerPeer that drives Godot's multiplayer API
var _webrtc_multiplayer : WebRTCMultiplayerPeer = null

# ---------------------------------------------------------------------------
# Public read-only helpers
# ---------------------------------------------------------------------------

func get_match_id() -> String:
    return _match_id

func get_my_session_id() -> String:
    return _my_session_id

func get_players() -> Dictionary:
    return _players.duplicate()

# ---------------------------------------------------------------------------
# Required by NakamaWebRTCNetworkAdaptor
# ---------------------------------------------------------------------------

## Returns the Player whose Godot peer_id matches p_peer_id, or null.
func get_player_by_peer_id(p_peer_id: int) -> Player:
    for player in _players.values():
        if player.peer_id == p_peer_id:
            return player
    return null

## Returns the WebRTCPeerConnection for a given Nakama session_id, or null.
func get_webrtc_peer(p_session_id: String) -> WebRTCPeerConnection:
    return _webrtc_peers.get(p_session_id, null)

# ---------------------------------------------------------------------------
# Connection & authentication
# ---------------------------------------------------------------------------

## Connects to a Nakama server and authenticates via device ID.
## p_server_key defaults to "defaultkey" (the Nakama development default).
## Emits connected_to_nakama() on success, error(message) on failure.
func connect_to_nakama(
        p_host       : String = "127.0.0.1",
        p_port       : int    = 7350,
        p_server_key : String = "defaultkey",
        p_use_ssl    : bool   = false) -> void:

    var scheme := "https" if p_use_ssl else "http"
    _nakama_client = Nakama.create_client(p_server_key, p_host, p_port, scheme)

    var device_id := _get_or_create_device_id()
    var session_result = await _nakama_client.authenticate_device_async(device_id)

    if session_result.is_exception():
        emit_signal("error", "Nakama auth failed: %s" % session_result.get_exception().message)
        return

    _nakama_session   = session_result

    _nakama_socket = Nakama.create_socket_from(_nakama_client)
    var conn_result = await _nakama_socket.connect_async(_nakama_session)

    if conn_result.is_exception():
        emit_signal("error", "Nakama socket connect failed: %s" % conn_result.get_exception().message)
        return

    _nakama_socket.received_match_presence.connect(_on_received_match_presence)
    _nakama_socket.received_match_state.connect(_on_received_match_state)
    _nakama_socket.closed.connect(_on_socket_closed)

    emit_signal("connected_to_nakama")

# ---------------------------------------------------------------------------
# Match lifecycle
# ---------------------------------------------------------------------------

## Creates a private Nakama match. Emits match_created(match_id) on success.
func create_match() -> void:
    if not _nakama_socket:
        emit_signal("error", "Not connected to Nakama. Call connect_to_nakama() first.")
        return

    var match_result = await _nakama_socket.create_match_async()

    if match_result.is_exception():
        emit_signal("error", "create_match failed: %s" % match_result.get_exception().message)
        return

    _match_id = match_result.match_id
    _my_session_id = match_result.self_user.session_id
    _setup_webrtc_multiplayer()
    emit_signal("match_created", _match_id)

## Joins an existing Nakama match by ID. Emits match_joined(match_id) on success.
func join_match(p_match_id: String) -> void:
    if not _nakama_socket:
        emit_signal("error", "Not connected to Nakama. Call connect_to_nakama() first.")
        return

    var match_result = await _nakama_socket.join_match_async(p_match_id)

    if match_result.is_exception():
        emit_signal("error", "join_match failed: %s" % match_result.get_exception().message)
        return

    _match_id = match_result.match_id
    _my_session_id = match_result.self_user.session_id
    _setup_webrtc_multiplayer()

    # Process presences that are already in the match.
    for presence in match_result.presences:
        if presence.session_id != _my_session_id:
            _add_player(presence)

    emit_signal("match_joined", _match_id)

## Leaves the current match and tears down WebRTC. Emits match_left().
func leave_match() -> void:
    if _nakama_socket and _match_id != "":
        await _nakama_socket.leave_match_async(_match_id)

    _cleanup_match()
    emit_signal("match_left")

# ---------------------------------------------------------------------------
# Private — match state callbacks
# ---------------------------------------------------------------------------

func _on_received_match_presence(event: NakamaRTAPI.MatchPresenceEvent) -> void:
    if event.match_id != _match_id:
        return

    for presence in event.joins:
        if presence.session_id != _my_session_id:
            _add_player(presence)

    for presence in event.leaves:
        _remove_player(presence)

func _on_received_match_state(data: NakamaRTAPI.MatchData) -> void:
    if data.match_id != _match_id:
        return

    var sender_session_id : String = data.presence.session_id
    var payload : String = data.data

    match data.op_code:
        OP_WEBRTC_OFFER:
            if _webrtc_peers.has(sender_session_id):
                var peer : WebRTCPeerConnection = _webrtc_peers[sender_session_id]
                peer.set_remote_description("offer", payload)
                _flush_pending_ice_candidates(sender_session_id)

        OP_WEBRTC_ANSWER:
            if _webrtc_peers.has(sender_session_id):
                var peer : WebRTCPeerConnection = _webrtc_peers[sender_session_id]
                peer.set_remote_description("answer", payload)
                _flush_pending_ice_candidates(sender_session_id)

        OP_WEBRTC_ICE_CANDIDATE:
            if _webrtc_peers.has(sender_session_id):
                var peer : WebRTCPeerConnection = _webrtc_peers[sender_session_id]
                var parts := payload.split("\n", false)
                if parts.size() == 3:
                    if peer.get_connection_state() == WebRTCPeerConnection.STATE_NEW:
                        # Remote description not yet set; buffer the candidate.
                        if not _pending_ice_candidates.has(sender_session_id):
                            _pending_ice_candidates[sender_session_id] = []
                        _pending_ice_candidates[sender_session_id].append(
                            {"mid": parts[0], "index": int(parts[1]), "sdp": parts[2]})
                    else:
                        peer.add_ice_candidate(parts[0], int(parts[1]), parts[2])

func _on_socket_closed() -> void:
    emit_signal("disconnected")
    _cleanup_match()

# ---------------------------------------------------------------------------
# Private — player management
# ---------------------------------------------------------------------------

func _add_player(presence) -> void:
    if _players.has(presence.session_id):
        return

    # Assign peer IDs deterministically: sort all session IDs (including self),
    # lowest index = 1 (host), rest get 2..N.
    var all_ids : Array = _players.keys()
    all_ids.append(presence.session_id)
    if not all_ids.has(_my_session_id):
        all_ids.append(_my_session_id)
    all_ids.sort()

    # Rebuild peer IDs for every player to stay consistent.
    for i in all_ids.size():
        var sid : String = all_ids[i]
        var pid : int    = i + 1
        if sid == presence.session_id:
            var player := Player.new(sid, pid, presence.username, presence)
            _players[sid] = player
        elif _players.has(sid):
            _players[sid].peer_id = pid

    # Re-assign our own peer_id in the multiplayer peer.
    # create_mesh() can only be called once per WebRTCMultiplayerPeer instance,
    # so we must recreate it with the now-correct peer_id. All existing peer
    # connections must be torn down first — they cannot be re-added because
    # add_peer() requires STATE_NEW and they have already started ICE negotiation.
    if _webrtc_multiplayer:
        # Tear down every existing peer connection before rebuilding the mesh.
        for sid in _webrtc_peers:
            var old_peer : WebRTCPeerConnection = _webrtc_peers[sid]
            if _players.has(sid):
                emit_signal("webrtc_peer_removed", old_peer, _players[sid])
            old_peer.close()
        _webrtc_peers.clear()
        _pending_ice_candidates.clear()

        var correct_id := _peer_id_for_session(_my_session_id)
        _webrtc_multiplayer = WebRTCMultiplayerPeer.new()
        _webrtc_multiplayer.create_mesh(correct_id)
        multiplayer.multiplayer_peer = _webrtc_multiplayer

    # Set up fresh WebRTC connections for all known players (including the new one).
    for sid in _players:
        _setup_webrtc_peer(sid)

    var player : Player = _players[presence.session_id]
    emit_signal("player_joined", player)

func _remove_player(presence) -> void:
    if not _players.has(presence.session_id):
        return

    var player : Player = _players[presence.session_id]

    if _webrtc_peers.has(presence.session_id):
        var peer : WebRTCPeerConnection = _webrtc_peers[presence.session_id]
        emit_signal("webrtc_peer_removed", peer, player)
        peer.close()
        _webrtc_peers.erase(presence.session_id)
        _webrtc_multiplayer.remove_peer(player.peer_id)

    _players.erase(presence.session_id)
    emit_signal("player_left", player)
    emit_signal("match_not_ready")

# ---------------------------------------------------------------------------
# Private — WebRTC setup
# ---------------------------------------------------------------------------

func _setup_webrtc_multiplayer() -> void:
    _webrtc_multiplayer = WebRTCMultiplayerPeer.new()
    _webrtc_multiplayer.create_mesh(_peer_id_for_session(_my_session_id))
    multiplayer.multiplayer_peer = _webrtc_multiplayer

## Creates a WebRTCPeerConnection for the given session_id.
## Offerer is decided deterministically: the peer with the lexicographically
## smaller session_id creates the offer.
func _setup_webrtc_peer(p_session_id: String) -> void:
    if _webrtc_peers.has(p_session_id):
        return

    var peer := WebRTCPeerConnection.new()
    peer.initialize({
        "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]
    })

    var player : Player = _players.get(p_session_id)
    if player == null:
        return

    _webrtc_peers[p_session_id] = peer
    _webrtc_multiplayer.add_peer(peer, player.peer_id)

    peer.session_description_created.connect(
        func(type: String, sdp: String) -> void:
            _on_webrtc_session_description_created(p_session_id, type, sdp)
    )
    peer.ice_candidate_created.connect(
        func(media: String, index: int, sdp_line: String) -> void:
            _on_webrtc_ice_candidate_created(p_session_id, media, index, sdp_line)
    )

    if _my_session_id.casecmp_to(p_session_id) < 0:
        peer.create_offer()

    emit_signal("webrtc_peer_added", peer, player)

func _on_webrtc_session_description_created(
        p_session_id : String,
        p_type       : String,
        p_sdp        : String) -> void:

    if not _webrtc_peers.has(p_session_id):
        return

    var peer : WebRTCPeerConnection = _webrtc_peers[p_session_id]
    peer.set_local_description(p_type, p_sdp)

    var op_code := OP_WEBRTC_OFFER if p_type == "offer" else OP_WEBRTC_ANSWER
    _send_match_data_to(p_session_id, op_code, p_sdp)

func _on_webrtc_ice_candidate_created(
        p_session_id : String,
        p_media      : String,
        p_index      : int,
        p_sdp_line   : String) -> void:

    _send_match_data_to(p_session_id, OP_WEBRTC_ICE_CANDIDATE,
        "%s\n%d\n%s" % [p_media, p_index, p_sdp_line])

func _flush_pending_ice_candidates(p_session_id: String) -> void:
    if not _pending_ice_candidates.has(p_session_id):
        return
    var peer : WebRTCPeerConnection = _webrtc_peers.get(p_session_id)
    if peer == null:
        _pending_ice_candidates.erase(p_session_id)
        return
    for cand in _pending_ice_candidates[p_session_id]:
        peer.add_ice_candidate(cand["mid"], cand["index"], cand["sdp"])
    _pending_ice_candidates.erase(p_session_id)

# ---------------------------------------------------------------------------
# Private — Nakama match data helpers
# ---------------------------------------------------------------------------

## Send to all presences in the match.
func _send_match_data(p_op_code: int, p_data: String) -> void:
    if _nakama_socket and _match_id != "":
        _nakama_socket.send_match_state_async(_match_id, p_op_code, p_data)

## Send to a single session_id only.
func _send_match_data_to(p_session_id: String, p_op_code: int, p_data: String) -> void:
    if not (_nakama_socket and _match_id != ""):
        return

    # Unicast: pass the target presence so only the intended peer receives the
    # offer/answer/ICE-candidate. Broadcasting was the root cause of the ICE
    # restart and ufrag mismatch errors with 3+ players.
    var player : Player = _players.get(p_session_id)
    if player == null or player.presence == null:
        return
    _nakama_socket.send_match_state_async(_match_id, p_op_code, p_data, [player.presence])

# ---------------------------------------------------------------------------
# Private — poll WebRTC state, emit match_ready when all peers are connected
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
    if _webrtc_multiplayer == null or _players.is_empty():
        return

    _webrtc_multiplayer.poll()

    # Check that every expected peer is connected.
    var all_connected := true
    for session_id in _players:
        if not _webrtc_peers.has(session_id):
            all_connected = false
            break
        var peer : WebRTCPeerConnection = _webrtc_peers[session_id]
        if peer.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED:
            all_connected = false
            break

    if all_connected and _players.size() >= 1:
        # Fire once per transition to "all connected".
        if not _match_ready_emitted:
            _match_ready_emitted = true
            emit_signal("match_ready", _players.duplicate())
    else:
        if _match_ready_emitted:
            _match_ready_emitted = false
            emit_signal("match_not_ready")

var _match_ready_emitted : bool = false

# ---------------------------------------------------------------------------
# Private — utilities
# ---------------------------------------------------------------------------

func _peer_id_for_session(p_session_id: String) -> int:
    var all_ids : Array = _players.keys()
    if not all_ids.has(p_session_id):
        all_ids.append(p_session_id)
    all_ids.sort()
    return all_ids.find(p_session_id) + 1

## Returns or creates a stable device ID stored in user://device_id.txt.
func _get_or_create_device_id() -> String:
    var path := "user://device_id.txt"
    if FileAccess.file_exists(path):
        var f := FileAccess.open(path, FileAccess.READ)
        if f:
            var id := f.get_as_text().strip_edges()
            f.close()
            if id.length() > 0:
                return id

    # Generate a new UUID-style random ID.
    var id := "%s-%s-%s-%s" % [
        _random_hex(8), _random_hex(4), _random_hex(4), _random_hex(8)
    ]
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f:
        f.store_string(id)
        f.close()
    return id

func _random_hex(p_length: int) -> String:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var result := ""
    for i in p_length:
        result += "%x" % rng.randi_range(0, 15)
    return result

# ---------------------------------------------------------------------------
# Private — cleanup
# ---------------------------------------------------------------------------

func _cleanup_match() -> void:
    for session_id in _webrtc_peers:
        _webrtc_peers[session_id].close()
    _webrtc_peers.clear()
    _pending_ice_candidates.clear()
    _players.clear()
    _match_id = ""
    _match_ready_emitted = false

    if _webrtc_multiplayer:
        multiplayer.multiplayer_peer = null
        _webrtc_multiplayer = null
