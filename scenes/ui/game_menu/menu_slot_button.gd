class_name MenuSlotButton
extends Button
## Icon button of the inventory and tools tabs (Unity InventoryItemButton + the item slot prefabs): flat button
## showing the item icon, with the SelectFrame shown only while it has focus. `selected` fires when it gains
## focus (Unity ISelectHandler.OnSelect). Look and size come from menu_slot_button.tscn (Icon, SelectFrame and,
## in inventory_key_slot.tscn, Amount); the page places / instances it and sets the icon.

signal selected(slot: MenuSlotButton)

## Item id (inventory tab) or kind * 100 + tool id (tools tab).
@export var item_id: int = -1

@onready var icon_rect: TextureRect = $Icon
@onready var frame: TextureRect = $SelectFrame
## Only the Cool Key slot scene has an "Amount" label.
@onready var amount_label: Label = get_node_or_null("Amount") as Label

func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	mouse_entered.connect(grab_focus)

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
