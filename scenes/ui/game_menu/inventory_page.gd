class_name InventoryPage
extends MenuPage
## Port of InventoryPage.cs / InventoryItemButton.cs / InventoryInfoBox.cs (+ the InventoryGroup layout of
## InventoryMenu.prefab). Layout lives in pages/inventory_page.tscn: Mask, Silk Spool and Needle are placed
## slots (always shown); the grid shows Verdant Mantle, Notebook and Quill, Carapace Backpack, Silkbind
## Sandal, Cool Key in that order, only with amount > 0. The grid slots (menu_slot_button.tscn, or
## inventory_key_slot.tscn for a Cool Key stack) are instanced on show and destroyed on hide, like Unity.

const SLOT_SCENE := preload("res://scenes/ui/game_menu/menu_slot_button.tscn")
const KEY_SLOT_SCENE := preload("res://scenes/ui/game_menu/inventory_key_slot.tscn")

var static_slots: Dictionary = {} # item id -> MenuSlotButton
var grid_slots: Array[MenuSlotButton] = []

@onready var name_label: Label = $Name
@onready var desc_label: Label = $Desc
@onready var _grid_root: Control = $InventoryGrid

func _ready() -> void:
	for slot: MenuSlotButton in [$Needle, $Mask, $SilkSpool]:
		slot.selected.connect(_on_slot_selected)
		static_slots[slot.item_id] = slot

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
		# Only the Cool Key slot prefab has an "Amount" text (shown when amount > 1).
		var with_amount: bool = item == InventoryIds.ItemName.COOL_KEY and amount > 1
		var slot := (KEY_SLOT_SCENE if with_amount else SLOT_SCENE).instantiate() as MenuSlotButton
		slot.item_id = item
		slot.name = String(GameMenuData.ITEMS[item]["name"]).replace(" ", "")
		slot.position = GameMenuData.rect_px(cell_center, Vector2.ONE * GameMenuData.GRID_CELL).position
		slot.selected.connect(_on_slot_selected)
		_grid_root.add_child(slot)
		var data: Dictionary = GameMenuData.ITEMS[item]
		slot.icon_rect.texture = GameMenuData.load_texture(data["icon"], data.get("icon_region", Rect2()))
		if with_amount:
			slot.amount_label.text = str(amount)
		grid_slots.append(slot)
		index += 1

## InventoryItemButton.OnSelect: moving sound + info box.
func _on_slot_selected(slot: MenuSlotButton) -> void:
	play_moving()
	var data: Dictionary = GameMenuData.ITEMS[slot.item_id]
	name_label.text = data["name"]
	desc_label.text = data["desc"]
