@tool
extends EditorPlugin


const node_tree_shell_core_path = "res://addons/godot-node-tree-shell/NodeTreeShellCore.tscn"


func _enable_plugin() -> void:
    add_autoload_singleton("NodeTreeShellCore", node_tree_shell_core_path)


func _disable_plugin() -> void:
    remove_autoload_singleton("NodeTreeShellCore")


func _enter_tree() -> void:
    # Initialization of the plugin goes here.
    pass


func _exit_tree() -> void:
    # Clean-up of the plugin goes here.
    pass
