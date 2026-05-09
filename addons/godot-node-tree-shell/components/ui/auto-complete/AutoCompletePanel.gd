extends Panel

signal candidate_selected(base_text: String, candidate: String)

const AutoCompleteButton = preload("res://addons/godot-node-tree-shell/components/ui/auto-complete/AutoCompleteButton.tscn")

@onready var _vbox: VBoxContainer = %VBoxContainer
@onready var _scroll_container: ScrollContainer = $ScrollContainer

var _line_edit: CommandLineEdit = null
var _base_text: String = ""
var target_candidate_index: int = 0


func _ready() -> void:
    top_level = true
    hide()

func target_next_candidate() -> bool :
    if not visible:
        return false
    target_candidate_index = clamp(target_candidate_index + 1, 0, _vbox.get_child_count() - 1)
    update_target_candidate()
    return true

func target_previous_candidate() -> bool :
    if not visible:
        return false
    target_candidate_index = clamp(target_candidate_index - 1, 0, _vbox.get_child_count() - 1)
    update_target_candidate()
    return true

func select_target_candidate() -> bool:
    if not visible or _vbox.get_child_count() == 0:
        return false
    var target_candidate : Button = null
    if _vbox.get_child_count() > target_candidate_index:
        target_candidate = _vbox.get_child(target_candidate_index)
    if is_instance_valid(target_candidate):
        candidate_selected.emit(_base_text, target_candidate.text)
        return true
    return false

func update_target_candidate() :
    var target_candidate : Button = null
    if _vbox.get_child_count() > target_candidate_index:
        target_candidate = _vbox.get_child(target_candidate_index)
    for child in _vbox.get_children():
        child.untarget()
    if is_instance_valid(target_candidate):
        target_candidate.target()
        _scroll_container.ensure_control_visible(target_candidate)

func update_candidates(candidates: Array, base_text: String, line_edit: CommandLineEdit) -> void:
    _line_edit = line_edit
    _base_text = base_text

    for child in _vbox.get_children():
        _vbox.remove_child(child)
        child.queue_free()

    for candidate in candidates:
        var btn: Button = AutoCompleteButton.instantiate()
        _vbox.add_child(btn)
        btn.setup(base_text, candidate)
        btn.selected.connect(func(bt: String, c: String): candidate_selected.emit(bt, c))

    show()
    target_candidate_index = clamp(target_candidate_index, 0, _vbox.get_child_count() - 1)
    update_target_candidate()
    call_deferred("update_position")


func update_position() -> void:
    if not is_instance_valid(_line_edit):
        return
    var line_edit_rect = _line_edit.get_global_rect()
    var base_x = _get_base_text_width()
    var popup_x = clampf(line_edit_rect.position.x + base_x, 0.0, get_window().size.x - size.x)
    var popup_y = line_edit_rect.position.y + line_edit_rect.size.y
    position = Vector2(popup_x, popup_y)


func hide_candidates() -> void:
    for child in _vbox.get_children():
        _vbox.remove_child(child)
        child.queue_free()
    hide()

func is_open() -> bool:
    return visible

func _get_caret_x() -> float:
    if not is_instance_valid(_line_edit):
        return 0.0
    var font = _line_edit.get_theme_font("font")
    var font_size = _line_edit.get_theme_font_size("font_size")
    var text_before_caret = _line_edit.text.substr(0, _line_edit.caret_column)
    return font.get_string_size(text_before_caret, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func _get_base_text_width() -> float:
    if not is_instance_valid(_line_edit):
        return 0.0
    var font = _line_edit.get_theme_font("font")
    var font_size = _line_edit.get_theme_font_size("font_size")
    return font.get_string_size(_base_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
