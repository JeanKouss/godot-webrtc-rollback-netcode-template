extends Button

var _related_node: Node = null

var related_node: Node:
    set(value):
        _set_related_node(value)
    get:
        return _related_node

func _ready() -> void:
    pressed.connect(_on_pressed)
    _refresh_button_state()

func _exit_tree() -> void:
    _disconnect_related_node_signals()

func _on_pressed() -> void:
    if not is_instance_valid(_related_node) or not _related_node.is_inside_tree():
        disabled = true
        return
    NodeTreeShellCore.change_node(_related_node.get_path())

func _set_related_node(value: Node) -> void:
    if _related_node == value:
        _refresh_button_state()
        return

    _disconnect_related_node_signals()
    _related_node = value
    _connect_related_node_signals()
    _refresh_button_state()

func _connect_related_node_signals() -> void:
    if not is_instance_valid(_related_node):
        return
    if not _related_node.tree_entered.is_connected(_on_related_node_tree_entered):
        _related_node.tree_entered.connect(_on_related_node_tree_entered)
    if not _related_node.tree_exited.is_connected(_on_related_node_tree_exited):
        _related_node.tree_exited.connect(_on_related_node_tree_exited)

func _disconnect_related_node_signals() -> void:
    if not is_instance_valid(_related_node):
        return
    if _related_node.tree_entered.is_connected(_on_related_node_tree_entered):
        _related_node.tree_entered.disconnect(_on_related_node_tree_entered)
    if _related_node.tree_exited.is_connected(_on_related_node_tree_exited):
        _related_node.tree_exited.disconnect(_on_related_node_tree_exited)

func _refresh_button_state() -> void:
    disabled = not is_instance_valid(_related_node) or not _related_node.is_inside_tree()

func _on_related_node_tree_entered() -> void:
    _refresh_button_state()

func _on_related_node_tree_exited() -> void:
    disabled = true
    call_deferred("_sync_related_node_state")

func _sync_related_node_state() -> void:
    if not is_instance_valid(_related_node):
        _related_node = null
        disabled = true
        return
    _refresh_button_state()
