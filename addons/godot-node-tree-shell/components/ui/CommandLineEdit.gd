class_name CommandLineEdit
extends Label

signal text_changed(new_text: String)

var command_text: String = "":
    set(value):
        command_text = value
        text = value
        text_changed.emit(value)
        _update_caret()

var _caret_column: int = 0:
    set(value):
        _caret_column = clampi(value, 0, command_text.length())
        _update_caret()

@onready var _caret: ColorRect = $CommandCaret

func _ready() -> void:
    _update_caret()

func clear() -> void:
    command_text = ""
    _caret_column = 0

func insert_at_caret(character: String) -> void:
    command_text = command_text.left(_caret_column) + character + command_text.substr(_caret_column)
    _caret_column += 1
    grab_focus()

func delete_before_caret() -> void:
    if _caret_column == 0:
        return
    command_text = command_text.left(_caret_column - 1) + command_text.substr(_caret_column)
    _caret_column -= 1

func delete_after_caret() -> void:
    if _caret_column >= command_text.length():
        return
    command_text = command_text.left(_caret_column) + command_text.substr(_caret_column + 1)

func move_caret_left() -> bool:
    if not has_focus() :
        return false
    _caret_column -= 1
    return true

func move_caret_right() -> bool:
    if not has_focus() :
        return false
    _caret_column += 1
    return true

func move_caret_home() -> void:
    _caret_column = 0

func move_caret_end() -> void:
    _caret_column = command_text.length()

func _update_caret() -> void:
    if not is_instance_valid(_caret):
        return
    var font_size: int = get_theme_font_size("font_size")
    var offset_x: float = get_theme_font("font").get_string_size(
        command_text.left(_caret_column), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
    ).x
    _caret.position.x = offset_x
    _caret.size.y = size.y
