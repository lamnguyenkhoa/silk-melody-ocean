class_name JournalPage
extends MenuPage
## Port of JournalPage.cs / JournalButton.cs / JournalInfoBox.cs / JournalEnemyImage.cs. One row per
## EnemyLore (kill count 0: "???" + black silhouette + empty info; otherwise the lore). The list scrolls so
## that the selected row is centred (JournalButton.OnSelect sets the panel position) and remembers the last
## selected row while the menu object lives.

var rows: Array[SelectButton] = []
## EnemyType of each row.
var row_types: Array[int] = []
var glow: TextureRect
var enemy_image: TextureRect
var name_label: Label
var desc_label: Label
var flavor_label: Label
var kill_label: Label

var _list: Control
var _panel: Control
var _last_index: int = 0

func _ready() -> void:
	for bar_center: Vector2 in GameMenuData.JOURNAL_BARS:
		add_child(GameMenuUi.make_rect(GameMenuData.rect_px(bar_center, GameMenuData.BAR_SIZE), GameMenuData.BAR_COLOR))

	# EnemyList (RectMask2D) > Panel (rows 450x100, spacing 20).
	var list_rect := GameMenuData.rect_px(GameMenuData.JOURNAL_LIST_CENTER, GameMenuData.JOURNAL_LIST_SIZE)
	_list = Control.new()
	_list.name = "EnemyList"
	_list.position = list_rect.position
	_list.size = list_rect.size
	_list.clip_contents = true
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.size = Vector2(GameMenuData.JOURNAL_ROW_SIZE.x, 700.0) * GameMenuData.CANVAS_TO_PX
	_panel.position.x = (list_rect.size.x - _panel.size.x) * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(_panel)

	var row_px: Vector2 = GameMenuData.JOURNAL_ROW_SIZE * GameMenuData.CANVAS_TO_PX
	var frame_outset: Vector2 = (GameMenuData.JOURNAL_ROW_FRAME - GameMenuData.JOURNAL_ROW_SIZE) * 0.5 * GameMenuData.CANVAS_TO_PX
	for lore_index in GameMenuData.LORE.size():
		var lore: Dictionary = GameMenuData.LORE[lore_index]
		if not GameMenuData.SHOW_UNLISTED_LORE and GameMenuData.UNLISTED_LORE.has(lore["type"]):
			continue
		var row := SelectButton.new()
		row.name = String(lore["name"]).replace(" ", "")
		row.font_size_px = GameMenuData.font_px(40)
		row.frame_outset = frame_outset
		row.size = row_px
		row.custom_minimum_size = row_px
		row.position = Vector2(0.0, rows.size() * GameMenuData.JOURNAL_ROW_STEP * GameMenuData.CANVAS_TO_PX)
		row.text = "???"
		_panel.add_child(row)
		row.focus_entered.connect(_on_row_focused.bind(rows.size()))
		rows.append(row)
		row_types.append(lore["type"])

	# EnemyImage: GreenGlow 600x600 with the sprite at its native size on top.
	glow = GameMenuUi.make_texture(load("res://assets/ui/GreenGlow.png") as Texture2D,
			GameMenuData.rect_px(GameMenuData.JOURNAL_IMAGE_CENTER, GameMenuData.JOURNAL_IMAGE_SIZE))
	glow.name = "EnemyImage"
	add_child(glow)
	enemy_image = TextureRect.new()
	enemy_image.name = "Image"
	enemy_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_image.stretch_mode = TextureRect.STRETCH_SCALE
	enemy_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_child(enemy_image)

	# EnemyInfoBox.
	var c: Vector2 = GameMenuData.JOURNAL_INFO_CENTER
	var info_size := GameMenuData.JOURNAL_NAME_SIZE
	name_label = GameMenuUi.make_label("", GameMenuData.text_rect_px(c, info_size, GameMenuData.JOURNAL_NAME_MARGIN),
			GameMenuData.font_px(40), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, GameMenuUi.BOLD)
	name_label.name = "Name"
	add_child(name_label)
	desc_label = GameMenuUi.make_label("", GameMenuData.text_rect_px(c + GameMenuData.JOURNAL_DESC_OFFSET, info_size,
			GameMenuData.JOURNAL_DESC_MARGIN), GameMenuData.font_px(36), HORIZONTAL_ALIGNMENT_FILL, VERTICAL_ALIGNMENT_TOP)
	desc_label.name = "Description"
	add_child(desc_label)
	add_child(GameMenuUi.make_rect(GameMenuData.rect_px(c + GameMenuData.JOURNAL_BAR_OFFSET, GameMenuData.JOURNAL_BAR_SIZE),
			GameMenuData.BAR_COLOR))
	flavor_label = GameMenuUi.make_label("", GameMenuData.text_rect_px(c + GameMenuData.JOURNAL_FLAVOR_OFFSET, info_size,
			GameMenuData.JOURNAL_FLAVOR_MARGIN), GameMenuData.font_px(36), HORIZONTAL_ALIGNMENT_FILL, VERTICAL_ALIGNMENT_TOP,
			GameMenuUi.ITALIC)
	flavor_label.name = "FlavorText"
	add_child(flavor_label)
	kill_label = GameMenuUi.make_label("Defeated: 0", GameMenuData.text_rect_px(c + GameMenuData.JOURNAL_KILL_OFFSET, info_size,
			GameMenuData.JOURNAL_KILL_MARGIN), GameMenuData.font_px(36))
	kill_label.name = "KillCount"
	add_child(kill_label)

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
	enemy_image.texture = GameMenuUi.load_texture(lore["texture"], region)
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
	_panel.position.y = _list.size.y * 0.5 - (50.0 + GameMenuData.JOURNAL_ROW_STEP * row) * GameMenuData.CANVAS_TO_PX
	_last_index = row
