extends HBoxContainer

@onready var line_edit : CommandLineEdit = $CommandLineEdit
@onready var _autocomplete_panel = $AutoCompletePanel

var history_selection_index: int = 0

func _ready() -> void:
    NodeTreeShellCore.current_node_changed.connect(_on_current_node_changed)
    NodeTreeShellCore.command_execution_finished.connect(_on_command_execution_finished)
    _update_current_node_path(NodeTreeShellCore.current_node)
    line_edit.text_changed.connect(_on_text_changed)
    _autocomplete_panel.candidate_selected.connect(_on_autocomplete_selected)


func _on_current_node_changed(new_node: Node) -> void:
    _update_current_node_path(new_node)

func _on_command_execution_finished(_result: Variant, _show_as: String) -> void:
    show()
    _autocomplete_panel.hide_candidates()

func _exit_tree() -> void:
    _autocomplete_panel.hide_candidates()

func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed:
        return
    _handle_key(event)

func _handle_key(event: InputEventKey) -> void:
    match event.keycode:
        KEY_ENTER, KEY_KP_ENTER:
            if _autocomplete_panel.select_target_candidate() :
                get_viewport().set_input_as_handled()
                return
            var command = clean_input_text(line_edit.command_text)
            if command:
                line_edit.clear()
                hide()
                _autocomplete_panel.hide_candidates()
                NodeTreeShellCore.execute_command(command)  
                get_viewport().set_input_as_handled()
        KEY_ESCAPE:
            if _autocomplete_panel.is_open() :
                _autocomplete_panel.hide_candidates()
                get_viewport().set_input_as_handled()
        KEY_BACKSPACE:
            line_edit.delete_before_caret()
            get_viewport().set_input_as_handled()
        KEY_DELETE:
            line_edit.delete_after_caret()
            get_viewport().set_input_as_handled()
        KEY_HOME:
            line_edit.move_caret_home()
            get_viewport().set_input_as_handled()
        KEY_END:
            line_edit.move_caret_end()
            get_viewport().set_input_as_handled()
        KEY_LEFT:
            if line_edit.move_caret_left(): 
                # Only mark as handled if the line_edit is focused, to allow keyboard navigation
                get_viewport().set_input_as_handled()
        KEY_RIGHT:
            if line_edit.move_caret_right():
                get_viewport().set_input_as_handled()
        KEY_UP:
            if _autocomplete_panel.target_previous_candidate():
                get_viewport().set_input_as_handled()
            else :
                _show_history_up()
                get_viewport().set_input_as_handled()
        KEY_DOWN:
            if _autocomplete_panel.target_next_candidate():
                get_viewport().set_input_as_handled()
            else :
                _show_history_down()
                get_viewport().set_input_as_handled()
        KEY_F4:
            NodeTreeShellCore.terminal_visibility_toggle_requested.emit()
            get_viewport().set_input_as_handled()
        _:
            if event.unicode > 0:
                line_edit.insert_at_caret(char(event.unicode))
                get_viewport().set_input_as_handled()


func _on_text_changed(new_text: String) -> void:
    var result = NodeTreeShellCore.get_autocomplete_candidates(new_text)
    if result["candidates"].is_empty():
        _autocomplete_panel.hide_candidates()
        return
    _autocomplete_panel.update_candidates(result["candidates"], result["base_text"], line_edit)


func _on_autocomplete_selected(base_text: String, candidate: String) -> void:
    line_edit.command_text = base_text + candidate
    line_edit.move_caret_end()
    _on_text_changed(line_edit.command_text)
    _autocomplete_panel.hide_candidates() # Comes after to avoid showing auto-comp after selection


func _update_current_node_path(node: Node) -> void:
    %CurrentNodePath.text = node.get_path()

func _show_history_up() -> void:
    history_selection_index -= 1
    if abs(history_selection_index) > NodeTreeShellCore.get_command_history_size():
        history_selection_index += 1
    var cmd = NodeTreeShellCore.get_command_history_index(history_selection_index)
    line_edit.command_text = cmd
    line_edit.move_caret_end()
    _autocomplete_panel.hide_candidates() # Avoid showing auto-comp after selection
    line_edit.grab_focus()

func _show_history_down() -> void:
    history_selection_index += 1
    if history_selection_index > 0:
        history_selection_index = 0
    var cmd = NodeTreeShellCore.get_command_history_index(history_selection_index)
    line_edit.command_text = cmd
    line_edit.move_caret_end()
    _autocomplete_panel.hide_candidates() # Avoid showing auto-comp after selection
    line_edit.grab_focus()

func clean_input_text(input: String) -> String:
    input = input.strip_edges()
    return input
