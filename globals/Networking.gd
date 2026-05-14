# This file is messy
extends Node

signal network_mesh_joined
signal peer_joined_mesh(peer_id: int)

var has_emitted_mesh_joined : bool = false

var auto_start_sync_manager : bool = true
    
func _ready() -> void:
    get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
    get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)
    OnlineMatch.match_created.connect(_on_match_created)
    OnlineMatch.player_joined.connect(_on_player_joined_online_match)


func _on_player_joined_online_match(_player) -> void:
    # OnlineMatch just rebuilt the entire WebRTC mesh and reassigned ALL peer
    # IDs. Flush stale SyncManager entries so the upcoming peer_connected
    # events re-add peers with their correct new IDs.
    SyncManager.clear_peers()
    has_emitted_mesh_joined = false


func _on_peer_connected(id: int) -> void:
    if not SyncManager.has_peer(id):
        SyncManager.add_peer(id)
    print("-- Peer connected to %s with id: %s" % [get_tree().get_multiplayer().get_unique_id(), id])
    if not has_emitted_mesh_joined:
        has_emitted_mesh_joined = true
        network_mesh_joined.emit()
    peer_joined_mesh.emit(id)
    if get_tree().get_multiplayer().is_server() and auto_start_sync_manager: # If the id is 1
        print("++++++++++++++++++++ Starting SyncManager after 2 seconds delay")
        await get_tree().create_timer(2).timeout
        SyncManager.start()
        # Remenber to call SyncManager.stop()

func _on_peer_disconnected(id: int) -> void:
    SyncManager.remove_peer(id)
    print("-- Peer disconnected with id: %s" % id)

func _on_match_created(_match_id) -> void:
    var unique_id = get_tree().get_multiplayer().get_unique_id()
    print("-- Match created by peer with id: %s" % unique_id)
    
