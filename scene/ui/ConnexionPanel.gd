extends Control

var _match_code := ""

@onready var code_label: Button = %CodeLabel
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var create_game_button: Button = %CreateGameButton
@onready var join_game_button: Button = %JoinGameButton

func _ready() -> void:
    OnlineMatch.connected_to_nakama.connect(_on_connected_to_nakama)
    OnlineMatch.match_created.connect(_on_match_created)
    OnlineMatch.match_joined.connect(_on_match_joined)

    create_game_button.pressed.connect(create_match)
    join_game_button.pressed.connect(_on_join_game_pressed)
    code_label.pressed.connect(_on_code_label_pressed)

    OnlineMatch.connect_to_nakama()

func create_match():
    OnlineMatch.create_match()

func _on_join_game_pressed():
    var code := join_code_input.text.strip_edges()
    if code != "":
        connect_to_match(code)

func connect_to_match(id: String):
    OnlineMatch.join_match(id)


func _on_connected_to_nakama() -> void:
    print("Connected to Nakama!")

func _on_match_created(id) -> void:
    print("-- Match created with id: %s" % id)
    _match_code = id
    code_label.text = id

func _on_code_label_pressed() -> void:
    if _match_code != "":
        DisplayServer.clipboard_set(_match_code)
        code_label.text = "Copied!"
        await get_tree().create_timer(1.5).timeout
        code_label.text = _match_code

func _on_match_joined(id) -> void:
    print("-- Joined match with id: %s" % id)
    rpc("rpc_ping")

@rpc("any_peer", "call_remote", "reliable")
func rpc_ping() -> void:
    var sender_id = multiplayer.get_remote_sender_id()
    print("RPC ping received from peer: %s" % sender_id)
    if sender_id != 0:
        rpc_id(sender_id, "rpc_pong")

@rpc("any_peer", "call_remote", "reliable")
func rpc_pong() -> void:
    var sender_id = multiplayer.get_remote_sender_id()
    print("RPC pong received from peer: %s — RPC is working!" % sender_id)



func _on_hide_button_down() -> void:
    hide()
