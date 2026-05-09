extends Window

const NODE_TAG_SCENE: PackedScene = preload("res://addons/godot-node-tree-shell/components/ui/NodeTag.tscn")

@onready var shell_history = %ShellHistory
@onready var embeded_subwindows_warn_node = $EmbededSubwindowsWarnPan

func _ready() -> void:
    hide()
    NodeTreeShellCore.terminal_visibility_toggle_requested.connect(_on_terminal_visibility_toggle_request)
    NodeTreeShellCore.command_execution_requested.connect(_on_command_execution_requested)
    NodeTreeShellCore.command_execution_finished.connect(_on_command_execution_finished)
    var suppress: bool = ProjectSettings.get_setting("godot_node_tree_shell/suppress_embed_warning", false)
    var emb_subwind : bool = ProjectSettings.get_setting("display/window/subwindows/embed_subwindows")
    embeded_subwindows_warn_node.visible = emb_subwind and not suppress

func _on_command_execution_requested(command: String, on: Node) -> void:
    _append_command(command, on)
    

func _append_command(text: String, on: Node) -> void:
    var history_command_label = HBoxContainer.new()
    var path_label = Label.new()
    path_label.theme_type_variation = "CurrentDirLabel"
    path_label.text = "[%s]$" % on.get_path()
    history_command_label.add_child(path_label)
    var command_label = Label.new()
    command_label.text = " %s" % text
    history_command_label.add_child(command_label)
    shell_history.add_child(history_command_label)
    shell_history.move_child(history_command_label, -3) # Move to the second last position

func _on_command_execution_finished(result: Variant, show_as: String) -> void:
    match show_as:
        "text":
            var result_label = Label.new()
            result_label.text = str(result)
            shell_history.add_child(result_label)
            shell_history.move_child(result_label, -3) # Move to the second last position
        "list":
            var list_container = VBoxContainer.new()
            for item in result:
                var item_label = Label.new()
                item_label.text = str(item)
                list_container.add_child(item_label)
            shell_history.add_child(list_container)
            shell_history.move_child(list_container, -3)
        "node_list":
            var node_list_container = HFlowContainer.new()
            for item in result:
                var node_tag = NODE_TAG_SCENE.instantiate()
                if item is Node:
                    var node_item: Node = item
                    node_tag.text = node_item.name
                    node_tag.related_node = node_item
                else:
                    node_tag.text = str(item)
                node_list_container.add_child(node_tag)
            shell_history.add_child(node_list_container)
            shell_history.move_child(node_list_container, -3)
        "tree":
            var tree_container := VBoxContainer.new()
            _append_tree_node_tag(tree_container, result, 0)
            shell_history.add_child(tree_container)
            shell_history.move_child(tree_container, -3)
        "mute":
            pass # Do not show anything

func _append_tree_node_tag(container: VBoxContainer, data: Dictionary, depth: int) -> void:
    var row := HBoxContainer.new()
    var indentation := Control.new()
    indentation.custom_minimum_size = Vector2(depth * 16, 0)
    row.add_child(indentation)

    var node_tag = NODE_TAG_SCENE.instantiate()
    var node_value = data.get("node", null)
    if node_value is Node:
        var node_item: Node = node_value
        node_tag.text = str(data.get("name", node_item.name))
        node_tag.related_node = node_item
    else:
        node_tag.text = str(data.get("name", "Unnamed"))
        node_tag.disabled = true
    row.add_child(node_tag)

    container.add_child(row)

    for child_data in data.get("children", []):
        if child_data is Dictionary:
            _append_tree_node_tag(container, child_data, depth + 1)


func _on_keep_embeded_button_down() -> void:
    ProjectSettings.set_setting("godot_node_tree_shell/suppress_embed_warning", true)
    ProjectSettings.save()
    embeded_subwindows_warn_node.visible = false


func _on_desable_embeded_button_down() -> void:
    ProjectSettings.set_setting("display/window/subwindows/embed_subwindows", false)
    ProjectSettings.save()
    embeded_subwindows_warn_node.visible = false
    
func _on_terminal_visibility_toggle_request() -> void:
    visible = not visible