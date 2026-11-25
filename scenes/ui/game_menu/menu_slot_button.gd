class_name MenuSlotButton
extends Button
## Icon button of the inventory tab (Unity InventoryItemButton + the item slot prefabs): flat button showing
## the item icon, with the SelectFrame shown only while it has focus. `selected` fires when it gains focus
## (Unity ISelectHandler.OnSelect). Layout (position / size) is set by the page.

signal selected(slot: MenuSlotButton)

const FRAME_SQUARE := preload("res://assets/ui/SelectFrame.png")
const FRAME_LONG := preload("res://assets/ui/LongSelectFrame.png")

var item_id: int = -1
var icon_rect: TextureRect
var frame: TextureRect
var amount_label: Label

## Builds the child nodes. `frame_size` is the frame rect size (px), `long_frame` uses LongSelectFrame
## rotated by 90 degrees (the Needle slot: 892x227 frame on a 300x1200 image, rotated).
func setup(item: int, icon: Texture2D, slot_size: Vector2, long_frame: Vector2 = Vector2.ZERO) -> void:
	item_id = item
	size = slot_size
	custom_minimum_size = slot_size
	flat = true
	focus_mode = Control.FOCUS_ALL
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

	icon_rect = GameMenuUi.make_texture(icon, Rect2(Vector2.ZERO, slot_size))
	add_child(icon_rect)

	frame = TextureRect.new()
	frame.name = "SelectFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	if long_frame != Vector2.ZERO:
		frame.texture = FRAME_LONG
		var fsize: Vector2 = long_frame * GameMenuData.CANVAS_TO_PX
		frame.size = fsize
		frame.position = slot_size * 0.5 - fsize * 0.5
		frame.pivot_offset = fsize * 0.5
		# Unity rotates the child by +90 (counter-clockwise on screen); Godot rotation is clockwise.
		frame.rotation = -PI * 0.5
	else:
		frame.texture = FRAME_SQUARE
		frame.size = slot_size
	frame.visible = false
	add_child(frame)

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	mouse_entered.connect(grab_focus)

func set_amount_label(label: Label) -> void:
	amount_label = label
	add_child(label)

func is_frame_visible() -> bool:
	return frame != null and frame.visible

func _on_focus_entered() -> void:
	frame.visible = true
	selected.emit(self)

func _on_focus_exited() -> void:
	frame.visible = false

func _exit_tree() -> void:
	if frame != null:
		frame.visible = false
