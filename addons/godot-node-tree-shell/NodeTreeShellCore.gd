extends Node

signal command_execution_requested(command: String, on: Node)

signal current_node_changed(new_node: Node)

signal terminal_visibility_toggle_requested

## show_as can be "text", "list", "tree", "mute"
signal command_execution_finished(result: Variant, show_as: String)

enum AUTOCOMPLETE_TYPE {
    CURRENT_NODE_PROPERTY,
    CURRENT_NODE_FUNCTION,
}

@onready var current_node: Node = _get_default_current_node():
    set(val):
        current_node = val
        emit_signal("current_node_changed", val)
        _cache_current_node_properties()
        _cache_current_node_functions()
    get():
        if not current_node:
            return _get_default_current_node()
        return current_node

var current_node_properties: Dictionary = {}
var current_node_functions: Dictionary = {}

var _command_history: Array = []

var command_registry: Dictionary = {
    "help": {
        "name": "Help",
        "description": "List all available commands",
        "function": show_help,
        "parameters": [],
    },
    "lc": {
        "name": "List children",
        "description": "List the children of the current node",
        "function": list_children,
        "parameters": [],
    },
    "cn": {
        "name": "Change node/Current node",
        "description": "Change the current node/Show current node if no path is provided",
        "function": change_node,
        "parameters": ["path?"],
    },
    "get": {
        "name": "Get property value",
        "description": "Get the value of a property of the current node",
        "function": get_property_value,
        "parameters": ["property"],
        "autocomplete": {
            "property": AUTOCOMPLETE_TYPE.CURRENT_NODE_PROPERTY
        }
    },
    "set": {
        "name": "Set property",
        "description": "Set a property of the current node",
        "function": set_property_value,
        "parameters": ["property", "value"],
        "autocomplete": {
            "property": AUTOCOMPLETE_TYPE.CURRENT_NODE_PROPERTY
        }
    },
    "call": {
        "name": "Call function",
        "description": "Call a function of the current node",
        "function": call_node_method,
        "parameters": ["function_name", "..."],
        "autocomplete": {
            "function_name": AUTOCOMPLETE_TYPE.CURRENT_NODE_FUNCTION
        }
    },
    "tree": {
        "name": "Tree",
        "description": "Show the tree from the current node",
        "function": tree_command,
        "parameters": ["depth?"],
    },
    "history": {
        "name": "History",
        "description": "Show command history",
        "function": history_command,
        "parameters": ["n?"],
    },
}

func execute_command(command: String) -> void:
    if command.is_empty():
        command_execution_finished.emit("Command is empty", "mute")
        return
    command_execution_requested.emit(command, current_node)
    _command_history.append(command)
    var parsed_command = _parse_command(command)
    var cmd_dict: Dictionary = command_registry.get(parsed_command[0], {})
    if cmd_dict.is_empty():
        command_execution_finished.emit("Command not found", "text")
        return
    var cmd_function: Callable = cmd_dict['function']
    var cmd_params: Array = parsed_command.slice(1)
    if not _has_valid_parameter_count(cmd_dict, cmd_params):
        command_execution_finished.emit("Invalid parameters", "text")
        return
    print(cmd_function)
    print(cmd_params)
    cmd_function.callv(cmd_params)

#region Helpers

func get_command_history_size() -> int:
    return _command_history.size()

func get_command_history_index(index:int) -> String:
    if index >= 0:
        return ""
    if abs(index) > _command_history.size():
        return ""
    return _command_history[index]

func get_autocomplete_candidates(input: String) -> Dictionary:
    var empty := {"candidates": [], "base_text": ""}
    if input.is_empty():
        return empty
    var parsed_cmd = _parse_command(input)
    if parsed_cmd.is_empty():
        return empty
    var cmd_name: String = parsed_cmd[0]
    if not command_registry.has(cmd_name):
        return empty
    var cmd: Dictionary = command_registry[cmd_name]
    if not cmd.has("autocomplete"):
        return empty
    var has_trailing_space: bool = input[-1] == " "
    var args: Array = parsed_cmd.slice(1)
    var param_idx: int
    var partial: String
    var base_text: String
    if has_trailing_space:
        param_idx = args.size()
        partial = ""
        base_text = input
    else:
        if args.is_empty(): # The user is typing the command name
            return empty
        # The user is currently typing the parameter
        param_idx = args.size() - 1
        partial = args[param_idx]
        base_text = input.substr(0, input.length() - partial.length())
    var params: Array = cmd["parameters"]
    if param_idx >= params.size():
        return empty
    var param_name: String = str(params[param_idx]).trim_suffix("?")
    if not cmd["autocomplete"].has(param_name):
        return empty
    var autocomplete_type: int = cmd["autocomplete"][param_name]
    var source_keys: Array
    match autocomplete_type:
        AUTOCOMPLETE_TYPE.CURRENT_NODE_PROPERTY:
            source_keys = current_node_properties.keys()
        AUTOCOMPLETE_TYPE.CURRENT_NODE_FUNCTION:
            source_keys = current_node_functions.keys()
        _:
            return empty
    var candidates: Array = []
    for key in source_keys:
        if str(key).begins_with(partial):
            candidates.append(str(key))
    candidates.sort()
    return {"candidates": candidates, "base_text": base_text}


func _get_default_current_node() -> Node:
    return get_tree().get_root()

func _cache_current_node_properties() -> void:
    current_node_properties.clear()
    for property in current_node.get_property_list():
        current_node_properties[property.name] = {
            'type': property.type,
            'class_name': property.class_name
        }

func _cache_current_node_functions() -> void:
    current_node_functions.clear()
    for function in current_node.get_method_list():
        current_node_functions[function.name] = {
            'args': function.args,
        }

func _parse_command(command: String):
    # Split command into expressions separated by spaces that are not in quotes
    var regex = RegEx.new()
    regex.compile('"[^"]*"|\'[^\']*\'|\\S+')
    var result = []
    for m in regex.search_all(command):
        result.append(m.get_string())
    return result

func _has_valid_parameter_count(cmd_dict: Dictionary, cmd_params: Array) -> bool:
    var expected_params: Array = cmd_dict.get("parameters", [])
    if expected_params.is_empty():
        return cmd_params.is_empty()
    var has_variadic_parameter = expected_params[-1] == "..."
    if has_variadic_parameter:
        return cmd_params.size() >= expected_params.size() - 1
    var required_count := 0
    for parameter in expected_params:
        if not str(parameter).ends_with("?"):
            required_count += 1
    return cmd_params.size() >= required_count and cmd_params.size() <= expected_params.size()

func _format_parameter_list(parameters: Array) -> String:
    if parameters.is_empty():
        return "[]"
    var parameter_names := PackedStringArray()
    for parameter in parameters:
        parameter_names.append(str(parameter))
    return "[%s]" % ", ".join(parameter_names)

#endregion


#region Commands

func show_help() -> void:
    var command_names: Array = command_registry.keys()
    command_names.sort()

    var help_lines := []
    for command_name in command_names:
        var command_info: Dictionary = command_registry[command_name]
        help_lines.append(
            "%s: %s | params: %s" % [
                command_name,
                command_info.get("description", ""),
                _format_parameter_list(command_info.get("parameters", []))
            ]
        )

    command_execution_finished.emit(help_lines, "list")

func list_children() -> void:
    var children_nodes = []
    for child in current_node.get_children():
        children_nodes.append(child)
    command_execution_finished.emit(children_nodes, "node_list")

func change_node(path: String = "") -> void:
    if path.is_empty():
        command_execution_finished.emit(str(current_node.get_path()), "text")
        return

    var new_node = current_node.get_node_or_null(path)
    if new_node:
        current_node = new_node
        command_execution_finished.emit("Node changed", "mute")
    else:
        command_execution_finished.emit("Node not found", "text")

func get_property_value(property: String) -> void:
    if not current_node_properties.has(property):
        command_execution_finished.emit("Property not available on current node", "text")
        return
    var value = current_node.get(property)
    command_execution_finished.emit(value, "text")

func set_property_value(property: String, str_value: String) -> void:
    var expression = Expression.new()
    var error = expression.parse(str_value)
    if error:
        command_execution_finished.emit("Unable to parse value", "text")
        return
    var value = expression.execute()
    if expression.has_execute_failed():
        command_execution_finished.emit("Unable to parse value", "text")
        return
    if not current_node_properties.has(property):
        command_execution_finished.emit("Property not available on current node", "text")
        return
    var current_value = current_node.get(property)
    if typeof(value) != typeof(current_value):
        command_execution_finished.emit("Value type does not match property type. Got %s, expected %s" % [type_string(typeof(value)), type_string(typeof(current_value))], "text")
        return
    current_node.set(property, value)
    command_execution_finished.emit("Property set", "mute")

func call_node_method(function_name: String, ...args: Array) -> void:
    if not current_node_functions.has(function_name):
        command_execution_finished.emit("Function not available on current node", "text")
        return
    # evaluate every args
    for i in range(args.size()):
        var expression = Expression.new()
        var error = expression.parse(args[i])
        if error:
            command_execution_finished.emit("Unable to parse value", "text")
            return
        var value = expression.execute()
        if expression.has_execute_failed():
            command_execution_finished.emit("Unable to parse value", "text")
            return
        args[i] = value
    var result = current_node.callv(function_name, args)
    command_execution_finished.emit(result, "text")

func tree_command(depth: String = "1") -> void:
    if not depth.is_valid_int():
        command_execution_finished.emit("Depth must be an integer", "text")
        return

    var depth_int := depth.to_int()
    if depth_int <= 0:
        command_execution_finished.emit("Depth must be at least 1", "text")
        return

    var tree_data = _build_tree_data(current_node, depth_int)
    command_execution_finished.emit(tree_data, "tree")

func history_command(n: String = "20") -> void:
    if not n.is_valid_int():
        command_execution_finished.emit("n must be an integer", "text")
        return
    var h = get_command_history(n.to_int(), true)
    command_execution_finished.emit(h, "list")

func get_command_history(n: int = 20, skip_last: bool = false) -> Array:
    var end: int = _command_history.size() - (1 if skip_last else 0)
    if n == -1:
        return _command_history.slice(0, end)
    return _command_history.slice(max(0, end - n), end)

func _build_tree_data(node: Node, remaining_depth: int) -> Dictionary:
    var data := {
        "name": node.name,
        "node": node,
        "children": []
    }

    if remaining_depth <= 0:
        return data

    for child in node.get_children():
        data["children"].append(_build_tree_data(child, remaining_depth - 1))

    return data

#endregion


#region Utilities
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F4:
            terminal_visibility_toggle_requested.emit()
            get_viewport().set_input_as_handled()
#endregion