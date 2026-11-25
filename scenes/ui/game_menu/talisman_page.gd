class_name TalismanPage
extends MenuPage
## Placeholder of the "Tools" tab (index 1, the one `InventoryMenu` opens first). The talisman / tool UI
## (TalismanPage.cs, ToolButton, ...) is phase M2.

func _ready() -> void:
	var rect := GameMenuData.rect_px(Vector2(0.0, 0.0), Vector2(1200.0, 200.0))
	var label := GameMenuUi.make_label("Talisman and tools are not available yet.", rect,
			GameMenuData.font_px(40), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	label.name = "PlaceholderText"
	label.modulate = Color(1, 1, 1, 0.6)
	add_child(label)
