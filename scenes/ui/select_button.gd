class_name SelectButton
extends Button
## Menu button (Unity MainMenu.cs ISelectHandler / IDeselectHandler): the select frame is shown while the
## button has focus and the select sound plays when it gains focus. Flat look, centred white text.
## [signal chosen] is emitted on activation unless the button is [member inert] (Unity: "Continue" with no
## save is dimmed to alpha 0.2 and its handler does nothing; it can still be focused).

signal chosen

## Unity: Continue text colour alpha when there is no save.
const DIMMED_ALPHA: float = 0.2
## Unity: SelectFrame 400x100 on an 80 px (x1/5 scale) button strip; LongSelectFrame.png is 512x128.
const FRAME_TEXTURE := preload("res://assets/ui/LongSelectFrame.png")
const SELECT_SOUND := preload("res://assets/sfx/menu_button.ogg")
## Unity: TMP font size 50 on the 1920x1080 canvas -> /5 for the 384x216 viewport.
const FONT_SIZE: int = 10

## Still focusable but dimmed and silent on activation.
@export var inert: bool = false:
	set(value):
		inert = value
		_apply_dimming()

## Font size override (px); 0 keeps FONT_SIZE. Set before the button enters the tree.
@export var font_size_px: int = 0
## The select frame is the button rect grown by this much on every side (game menu journal rows: the
## 500x150 frame around a 450x100 button).
@export var frame_outset: Vector2 = Vector2.ZERO

## Skip the select sound for the next focus gain (the initial focus of a menu should be silent).
var mute_next_focus: bool = false

var _frame: TextureRect
var _sfx: AudioStreamPlayer

func _ready() -> void:
	# Menus are used while the tree is paused (pause menu) and by the main menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_mode = Control.FOCUS_ALL
	add_theme_font_size_override("font_size", font_size_px if font_size_px > 0 else FONT_SIZE)
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

	_frame = TextureRect.new()
	_frame.name = "SelectFrame"
	_frame.texture = FRAME_TEXTURE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = -frame_outset.x
	_frame.offset_right = frame_outset.x
	_frame.offset_top = -frame_outset.y
	_frame.offset_bottom = frame_outset.y
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SelectSound"
	_sfx.stream = SELECT_SOUND
	add_child(_sfx)

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)
	mouse_entered.connect(grab_focus)
	_apply_dimming()

func is_frame_visible() -> bool:
	return _frame != null and _frame.visible

func _on_focus_entered() -> void:
	_frame.visible = true
	if mute_next_focus:
		mute_next_focus = false
	else:
		_sfx.play()

func _on_focus_exited() -> void:
	_frame.visible = false

func _on_pressed() -> void:
	if not inert:
		chosen.emit()

func _apply_dimming() -> void:
	var c := Color(1, 1, 1, DIMMED_ALPHA if inert else 1.0)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(color_name, c)
