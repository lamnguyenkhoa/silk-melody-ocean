class_name JournalPage
extends MenuPage
## Port of JournalPage.cs / JournalButton.cs / JournalInfoBox.cs / JournalEnemyImage.cs. pages/journal_page.tscn
## places one JournalRow (journal_row.tscn) per EnemyLore in EnemyList > Panel, the enemy image on its glow and
## the info box labels. Kill count 0: "???" + black silhouette + empty info; otherwise the lore. The list
## scrolls so that the selected row is centred (JournalButton.OnSelect sets the panel position) and remembers
## the last selected row while the menu object lives.

var rows: Array[SelectButton] = []
## EnemyType of each row.
var row_types: Array[int] = []

var _last_index: int = 0

@onready var glow: TextureRect = $EnemyImage
@onready var enemy_image: TextureRect = $EnemyImage/Image
@onready var name_label: Label = $Name
@onready var desc_label: Label = $Description
@onready var flavor_label: Label = $FlavorText
@onready var kill_label: Label = $KillCount
@onready var _list: Control = $EnemyList
@onready var _panel: Control = $EnemyList/Panel

func _ready() -> void:
	for child in _panel.get_children():
		var row := child as JournalRow
		if row == null:
			continue
		row.focus_entered.connect(_on_row_focused.bind(rows.size()))
		rows.append(row)
		row_types.append(row.enemy_type)

## JournalButton.OnEnable: name or "???" from the kill count.
func page_shown() -> void:
	for i in rows.size():
		rows[i].text = row_name(i)

func initial_focus() -> Control:
	return rows[clampi(_last_index, 0, rows.size() - 1)] if not rows.is_empty() else null

func lore_of(row: int) -> Dictionary:
	for lore: Dictionary in GameMenuData.LORE:
		if lore["type"] == row_types[row]:
			return lore
	return {}

func kill_count_of(row: int) -> int:
	return GameState.get_kill_count(row_types[row])

func row_name(row: int) -> String:
	return "???" if kill_count_of(row) == 0 else String(lore_of(row)["name"])

## JournalButton.OnSelect.
func _on_row_focused(row: int) -> void:
	var lore: Dictionary = lore_of(row)
	var kills: int = kill_count_of(row)
	var region: Rect2 = lore["region"]
	enemy_image.texture = GameMenuData.load_texture(lore["texture"], region)
	# Image.SetNativeSize: rect size * referencePixelsPerUnit / spritePixelsPerUnit canvas units.
	var native: Vector2 = region.size * (GameMenuData.REFERENCE_PPU / GameMenuData.SPRITE_PPU) * GameMenuData.CANVAS_TO_PX
	enemy_image.size = native
	enemy_image.position = (glow.size - native) * 0.5
	kill_label.text = "Defeated: %d" % kills
	if kills > 0:
		enemy_image.modulate = Color.WHITE
		name_label.text = lore["name"]
		desc_label.text = lore["desc"]
		flavor_label.text = lore["flavour"]
	else:
		enemy_image.modulate = Color.BLACK # black silhouette
		name_label.text = ""
		desc_label.text = ""
		flavor_label.text = ""
	# Scroll: the selected row is centred in the list.
	_panel.position.y = _list.size.y * 0.5 - (rows[row].position.y + rows[row].size.y * 0.5)
	_last_index = row
