class_name TalismanView
extends Control
## One placed talisman crest (talisman_wanderer.tscn / talisman_sentinel.tscn): crest sprite, the red / blue /
## yellow slot sprites (each with an "Image" child that shows the equipped tool) and the name label. The talisman
## page shows the view whose `talisman_id` is the equipped talisman and hides the others.

@export var talisman_id: InventoryIds.TalismanName = InventoryIds.TalismanName.WANDERER

@onready var crest: TextureRect = $Crest
@onready var name_label: Label = $TalismanName
## Slot sprites per kind in slot order (RedSlot0, RedSlot1, ...): the node's child "Image" is the equipped tool.
var red_slots: Array[TextureRect] = []
var blue_slots: Array[TextureRect] = []
var yellow_slots: Array[TextureRect] = []

func _ready() -> void:
	for child in get_children():
		var slot := child as TextureRect
		if slot == null:
			continue
		if child.name.begins_with("RedSlot"):
			red_slots.append(slot)
		elif child.name.begins_with("BlueSlot"):
			blue_slots.append(slot)
		elif child.name.begins_with("YellowSlot"):
			yellow_slots.append(slot)
