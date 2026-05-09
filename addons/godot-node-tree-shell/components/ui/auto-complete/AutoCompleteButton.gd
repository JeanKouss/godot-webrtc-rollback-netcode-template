extends Button

var _is_targeted: bool = false
var targeted_style_box: StyleBox = preload("res://addons/godot-node-tree-shell/assets/theme-resources/auto-complete-button-targeted-style-box.tres")
var normal_style_box: StyleBox = preload("res://addons/godot-node-tree-shell/assets/theme-resources/auto-complete-button-normal-style-box.tres")

signal selected(base_text: String, candidate: String)

func target() :
    _is_targeted = true
    # set theme overrides icon normal color to white
    add_theme_color_override("icon_normal_color", Color(1, 1, 1))
    add_theme_stylebox_override("normal", targeted_style_box)

func untarget() :
    _is_targeted = false
    # Make theme overrides icon normal color transparent
    add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0))
    add_theme_stylebox_override("normal", normal_style_box)


func setup(base_text: String, candidate: String) -> void:
    text = candidate
    focus_mode = Control.FOCUS_NONE
    alignment = HORIZONTAL_ALIGNMENT_LEFT
    pressed.connect(func(): selected.emit(base_text, candidate))
