class_name InventoryPage
extends MenuPage
## Port of InventoryPage.cs / InventoryItemButton.cs / InventoryInfoBox.cs (+ the InventoryGroup layout of
## InventoryMenu.prefab). Mask, Silk Spool and Needle are static slots (always shown); the grid shows
## Verdant Mantle, Notebook and Quill, Carapace Backpack, Silkbind Sandal, Cool Key in that order, only
## with amount > 0. The grid slots are destroyed on hide and rebuilt on show, like Unity.

var static_slots: Dictionary = {} # item id -> MenuSlotButton
var grid_slots: Array[MenuSlotButton] = []
var name_label: Label
var desc_label: Label

var _grid_root: Control

func _ready() -> void:
	for bar_center: Vector2 in GameMenuData.INVENTORY_BARS:
		add_child(GameMenuUi.make_rect(GameMenuData.rect_px(bar_center, GameMenuData.BAR_SIZE), GameMenuData.BAR_COLOR))

	_grid_root = Control.new()
	_grid_root.name = "InventoryGrid"
	_grid_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid_root)

	# Static slots, in the prefab's child order (Mask, Needle, SilkSpool).
	for item: int in [InventoryIds.ItemName.NEEDLE, InventoryIds.ItemName.MASK, InventoryIds.ItemName.SILK_SPOOL]:
		var def: Dictionary = GameMenuData.STATIC_SLOTS[item]
		var slot := _make_slot(item, GameMenuData.rect_px(def["center"], def["size"]), def.get("long_frame", Vector2.ZERO))
		slot.name = String(GameMenuData.ITEMS[item]["name"]).replace(" ", "")
		add_child(slot)
		static_slots[item] = slot

	# Keyboard / gamepad navigation: the needle image overlaps the other two slots, so the automatic
	# (geometric) choice would send Down from the Mask to the Needle. Mask above Spool, Needle on the left.
	var mask_slot := static_slots[InventoryIds.ItemName.MASK] as MenuSlotButton
	var spool_slot := static_slots[InventoryIds.ItemName.SILK_SPOOL] as MenuSlotButton
	var needle_slot := static_slots[InventoryIds.ItemName.NEEDLE] as MenuSlotButton
	mask_slot.focus_neighbor_bottom = mask_slot.get_path_to(spool_slot)
	spool_slot.focus_neighbor_top = spool_slot.get_path_to(mask_slot)
	mask_slot.focus_neighbor_left = mask_slot.get_path_to(needle_slot)
	spool_slot.focus_neighbor_left = spool_slot.get_path_to(needle_slot)
	needle_slot.focus_neighbor_right = needle_slot.get_path_to(mask_slot)

	# InfoBox: Name + Desc.
	var center: Vector2 = GameMenuData.INVENTORY_INFO_CENTER
	name_label = GameMenuUi.make_label("", GameMenuData.text_rect_px(center, GameMenuData.INVENTORY_NAME_SIZE,
			GameMenuData.INVENTORY_NAME_MARGIN), GameMenuData.font_px(60), HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_CENTER, GameMenuUi.BOLD)
	name_label.name = "Name"
	add_child(name_label)
	desc_label = GameMenuUi.make_label("", GameMenuData.text_rect_px(center + GameMenuData.INVENTORY_DESC_OFFSET,
			GameMenuData.INVENTORY_DESC_SIZE, GameMenuData.INVENTORY_DESC_MARGIN), GameMenuData.font_px(36),
			HORIZONTAL_ALIGNMENT_FILL, VERTICAL_ALIGNMENT_TOP)
	desc_label.name = "Desc"
	add_child(desc_label)

func _make_slot(item: int, rect: Rect2, long_frame: Vector2 = Vector2.ZERO) -> MenuSlotButton:
	var data: Dictionary = GameMenuData.ITEMS[item]
	var icon: Texture2D = GameMenuUi.load_texture(data["icon"], data.get("icon_region", Rect2()))
	var slot := MenuSlotButton.new()
	slot.position = rect.position
	slot.setup(item, icon, rect.size, long_frame)
	slot.selected.connect(_on_slot_selected)
	return slot

func page_shown() -> void:
	_rebuild_grid()

func page_hidden() -> void:
	_clear_grid()

func initial_focus() -> Control:
	return static_slots[InventoryIds.ItemName.MASK] as Control

func _clear_grid() -> void:
	for slot: MenuSlotButton in grid_slots:
		if is_instance_valid(slot):
			_grid_root.remove_child(slot)
			slot.queue_free()
	grid_slots.clear()

## InventoryPage.AddSlotPrefabToGrid: GridLayoutGroup, 100x100 cells, spacing 40, 5 columns, upper left.
func _rebuild_grid() -> void:
	_clear_grid()
	var left: float = GameMenuData.GRID_CENTER.x - GameMenuData.GRID_SIZE.x * 0.5
	var top: float = GameMenuData.GRID_CENTER.y + GameMenuData.GRID_SIZE.y * 0.5
	var step: float = GameMenuData.GRID_CELL + GameMenuData.GRID_SPACING
	var index: int = 0
	for item: int in GameMenuData.GRID_ORDER:
		var amount: int = GameState.get_item_amount(item)
		if amount <= 0:
			continue
		var col: int = index % GameMenuData.GRID_COLUMNS
		var row: int = index / GameMenuData.GRID_COLUMNS
		var cell_center := Vector2(left + GameMenuData.GRID_CELL * 0.5 + col * step, top - GameMenuData.GRID_CELL * 0.5 - row * step)
		var slot := _make_slot(item, GameMenuData.rect_px(cell_center, Vector2.ONE * GameMenuData.GRID_CELL))
		slot.name = String(GameMenuData.ITEMS[item]["name"]).replace(" ", "")
		# Only the Cool Key slot prefab has an "Amount" text (shown when amount > 1).
		if item == InventoryIds.ItemName.COOL_KEY and amount > 1:
			var label_size := Vector2(100.0, 50.0) * GameMenuData.CANVAS_TO_PX
			var label := GameMenuUi.make_label(str(amount), Rect2(slot.size * 0.5 + GameMenuData.to_px(Vector2(35.4, -46.2)) - label_size * 0.5,
					label_size), GameMenuData.font_px(36))
			label.name = "Amount"
			slot.set_amount_label(label)
		_grid_root.add_child(slot)
		grid_slots.append(slot)
		index += 1

## InventoryItemButton.OnSelect: moving sound + info box.
func _on_slot_selected(slot: MenuSlotButton) -> void:
	play_moving()
	var data: Dictionary = GameMenuData.ITEMS[slot.item_id]
	name_label.text = data["name"]
	desc_label.text = data["desc"]
