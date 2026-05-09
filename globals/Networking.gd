extends Node

func _ready() -> void:
    get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
    get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)
    get_tree().get_multiplayer().connected_to_server.connect(_on_connected_to_server)
    OnlineMatch.match_created.connect(_on_match_created)


func _on_peer_connected(id: int) -> void:
    SyncManager.add_peer(id)
    print("-- Peer connected with id: %s" % id)
    if get_tree().get_multiplayer().is_server():
        await get_tree().create_timer(2).timeout
        SyncManager.start() # Delay the start, and call when there is one 1+ peer
        # Remenber to call SyncManager.stop()

func _on_peer_disconnected(id: int) -> void:
    SyncManager.remove_peer(id)
    print("-- Peer disconnected with id: %s" % id)

func _on_connected_to_server() -> void:
    var unique_id = get_tree().get_multiplayer().get_unique_id()
    print("-- Connected to server with id: %s" % unique_id)

func _on_match_created(_match_id) -> void:
    var unique_id = get_tree().get_multiplayer().get_unique_id()
    print("-- Match created by peer with id: %s" % unique_id)
    
