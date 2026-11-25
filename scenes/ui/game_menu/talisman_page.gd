class_name TalismanPage
extends MenuPage
## Port of the "Tools" tab (index 1): TalismanPage.cs, Talisman.cs (crest + slots), ChangeTalismanButton.cs,
## ToolButton.cs, ToolInfoBox.cs and the TalismanGroup of InventoryMenu.prefab. Equipping (tools and the
## talisman change) only works while the player rests on a chair, like Unity (`player.resting`); otherwise
## the red reminder text is shown. Blue and yellow tools can be equipped but have no gameplay (as in Unity).
##
## Layout (unity canvas units, relative to the screen centre, y up; see GameMenuData for the /5 scale):
##  - "Talisman" caption (-713, 335), ChangeTalisman button (-672, -432) with frame (+6, +4, 512x128) and
##    icon (-160, 0, 128x128), TalismanHolder (-558, -58) holding the 512x512 crest.
##  - ToolList: Panel top-left (-147.85, 354.63); DivideBar red / blue / yellow at y -60 / -290 / -520 and
##    the tool groups at y -130 / -360 / -590 (100x100 buttons, 140 apart). The Unity ScrollRect never has
##    anything to scroll (content 750 high in an 804 high view), so it is a static layout here.
##  - ToolInfoBox (669, 0): name, 256x256 image, description. Vertical Bar (398, -47.7).

const PANEL_TOP_LEFT := Vector2(-147.8485, 354.63)
const DIVIDE_BAR_SIZE := Vector2(475.85, 10.0)
const DIVIDE_ICON_SIZE := Vector2(100.0, 100.0)
## DivideBar Y offsets / Group Y offsets below the panel top, per tool kind (red, blue, yellow).
const DIVIDE_BAR_Y: Array[float] = [-60.0, -290.0, -520.0]
const GROUP_Y: Array[float] = [-130.0, -360.0, -590.0]
const GROUP_X: float = 47.925003
const TOOL_BUTTON_SIZE := Vector2(100.0, 100.0)
const TOOL_BUTTON_STEP: float = 140.0
const VERTICAL_BAR_CENTER := Vector2(398.0, -47.684998)
const TALISMAN_CAPTION_CENTER := Vector2(-713.0, 335.0)
const TEXT_BOX_SIZE := Vector2(200.0, 50.0)
const CHANGE_CENTER := Vector2(-672.0, -432.0)
const CHANGE_TEXT_MARGIN := Vector4(0.0, 0.0, -98.27519, -6.5534782)
const CHANGE_FRAME_OFFSET := Vector2(6.0, 4.0)
const CHANGE_FRAME_SIZE := Vector2(512.0, 128.0)
const CHANGE_ICON_OFFSET := Vector2(-160.0, 0.0)
const CHANGE_ICON_SIZE := Vector2(128.0, 128.0)
const HOLDER_CENTER := Vector2(-558.0, -58.0)
const CREST_SIZE := Vector2(512.0, 512.0)
## Talisman prefab root tint (0.3679245).
const CREST_TINT := Color(0.3679245, 0.3679245, 0.3679245)
const SLOT_SIZE := Vector2(128.0, 128.0)
const SLOT_ICON_SIZE := Vector2(100.0, 100.0)
const TALISMAN_NAME_OFFSET := Vector2(-159.04608, 354.99997)
const TALISMAN_NAME_MARGIN := Vector4(0.0, 0.0, -178.74272, -16.770338)
const REMINDER_CENTER := Vector2(-558.0, -38.894)
const REMINDER_SIZE := Vector2(517.189, 138.211)
const REMINDER_COLOR := Color(0.9528302, 0.0035955147, 0.0035955147)
const REMINDER_TEXT := "You can only change tools when resting at a chair"
const INFO_CENTER := Vector2(669.0, 0.0)
const INFO_NAME_OFFSET := Vector2(-85.0, 322.0)
const INFO_NAME_MARGIN := Vector4(-66.17787, 0.0, -254.3745, -16.770338)
const INFO_IMAGE_OFFSET := Vector2(3.0, 122.0)
const INFO_IMAGE_SIZE := Vector2(256.0, 256.0)
const INFO_DESC_OFFSET := Vector2(-85.00006, -84.0)
const INFO_DESC_MARGIN := Vector4(-39.108757, 0.0, -241.05655, -259.02515)
## ToolButton.UpdateEquipState: the icon of an equipped tool is drawn at alpha 0.3.
const EQUIPPED_ALPHA: float = 0.3
const TOOL_KINDS: Array[int] = [ToolData.ToolKind.RED, ToolData.ToolKind.BLUE, ToolData.ToolKind.YELLOW]

## Tool buttons per kind (index = ToolName value): test / navigation access.
var red_buttons: Array[MenuSlotButton] = []
var blue_buttons: Array[MenuSlotButton] = []
var yellow_buttons: Array[MenuSlotButton] = []
var change_button: Button
var change_frame: TextureRect
var info_name: Label
var info_image: TextureRect
var info_desc: Label
var reminder: RichTextLabel
var talisman_name_label: Label
var crest: TextureRect
## Slot rects of the shown talisman: per kind, the slot TextureRect (its child "Image" is the equipped tool).
var red_slots: Array[TextureRect] = []
var blue_slots: Array[TextureRect] = []
var yellow_slots: Array[TextureRect] = []

var _holder: Control
var _empty_tool: Texture2D
var _subscribed: bool = false

func _ready() -> void:
	_empty_tool = load(ToolData.EMPTY_TOOL_ICON) as Texture2D
	_build_caption_and_change_button()
	_build_tool_list()
	var bar := GameMenuUi.make_rect(GameMenuData.rect_px(VERTICAL_BAR_CENTER, GameMenuData.BAR_SIZE), GameMenuData.BAR_COLOR)
	bar.name = "Bar"
	add_child(bar)
	_build_info_box()
	_holder = GameMenuUi.make_origin(GameMenuData.SCREEN_CENTER + GameMenuData.to_px(HOLDER_CENTER))
	_holder.name = "TalismanHolder"
	add_child(_holder)
	_build_reminder()

# --- construction ---

func _build_caption_and_change_button() -> void:
	var caption := GameMenuUi.make_label("Talisman", GameMenuData.text_rect_px(TALISMAN_CAPTION_CENTER, TEXT_BOX_SIZE, Vector4.ZERO),
			GameMenuData.font_px(36), HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	caption.name = "TalismanText"
	add_child(caption)

	# The Button covers the select frame (the clickable / focusable area); text and icon are drawn on it.
	var frame_rect: Rect2 = GameMenuData.rect_px(CHANGE_CENTER + CHANGE_FRAME_OFFSET, CHANGE_FRAME_SIZE)
	change_button = Button.new()
	change_button.name = "ChangeTalisman"
	change_button.flat = true
	change_button.focus_mode = Control.FOCUS_ALL
	change_button.position = frame_rect.position
	change_button.size = frame_rect.size
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		change_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	add_child(change_button)
	change_frame = GameMenuUi.make_texture(MenuSlotButton.FRAME_LONG, Rect2(Vector2.ZERO, frame_rect.size))
	change_frame.name = "Frame"
	change_frame.visible = false
	change_button.add_child(change_frame)
	var icon_rect: Rect2 = GameMenuData.rect_px(CHANGE_CENTER + CHANGE_ICON_OFFSET, CHANGE_ICON_SIZE)
	var icon := GameMenuUi.make_texture(load("res://assets/ui/talisman/ChangeMaskIcon.png") as Texture2D,
			Rect2(icon_rect.position - frame_rect.position, icon_rect.size))
	icon.name = "Icon"
	change_button.add_child(icon)
	var text_rect: Rect2 = GameMenuData.text_rect_px(CHANGE_CENTER, TEXT_BOX_SIZE, CHANGE_TEXT_MARGIN)
	var text := GameMenuUi.make_label("Change Talisman", Rect2(text_rect.position - frame_rect.position, text_rect.size),
			GameMenuData.font_px(36), HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	text.name = "Text"
	change_button.add_child(text)
	change_button.focus_entered.connect(_on_change_focus_entered)
	change_button.focus_exited.connect(_on_change_focus_exited)
	change_button.mouse_entered.connect(change_button.grab_focus)
	change_button.pressed.connect(_on_change_pressed)

func _build_tool_list() -> void:
	var lists: Array = [red_buttons, blue_buttons, yellow_buttons]
	var slot_icons: Array[String] = [ToolData.RED_SLOT_ICON, ToolData.BLUE_SLOT_ICON, ToolData.YELLOW_SLOT_ICON]
	for kind: int in TOOL_KINDS:
		var bar_top: float = PANEL_TOP_LEFT.y + DIVIDE_BAR_Y[kind]
		var bar_center := Vector2(PANEL_TOP_LEFT.x + DIVIDE_BAR_SIZE.x * 0.5, bar_top - DIVIDE_BAR_SIZE.y * 0.5)
		var bar := GameMenuUi.make_rect(GameMenuData.rect_px(bar_center, DIVIDE_BAR_SIZE), GameMenuData.BAR_COLOR)
		bar.name = "DivideBar" + ["Red", "Blue", "Yellow"][kind]
		add_child(bar)
		var medal := GameMenuUi.make_texture(load(slot_icons[kind]) as Texture2D, GameMenuData.rect_px(bar_center, DIVIDE_ICON_SIZE))
		medal.name = "Image"
		add_child(medal)
		var tools: Array[Dictionary] = ToolData.tool_list(kind)
		var group_top: float = PANEL_TOP_LEFT.y + GROUP_Y[kind]
		for id in tools.size():
			var center := Vector2(PANEL_TOP_LEFT.x + GROUP_X + TOOL_BUTTON_SIZE.x * 0.5 + id * TOOL_BUTTON_STEP,
					group_top - TOOL_BUTTON_SIZE.y * 0.5)
			var rect: Rect2 = GameMenuData.rect_px(center, TOOL_BUTTON_SIZE)
			var button := MenuSlotButton.new()
			button.position = rect.position
			button.setup(kind * 100 + id, _empty_tool, rect.size)
			button.name = String(tools[id]["name"]).replace(" ", "")
			button.selected.connect(_on_tool_selected.bind(kind, id))
			button.pressed.connect(_on_tool_pressed.bind(kind, id))
			add_child(button)
			(lists[kind] as Array).append(button)

func _build_info_box() -> void:
	info_name = GameMenuUi.make_label("", GameMenuData.text_rect_px(INFO_CENTER + INFO_NAME_OFFSET, TEXT_BOX_SIZE, INFO_NAME_MARGIN),
			GameMenuData.font_px(48), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, GameMenuUi.BOLD)
	info_name.name = "ToolName"
	add_child(info_name)
	info_image = GameMenuUi.make_texture(null, GameMenuData.rect_px(INFO_CENTER + INFO_IMAGE_OFFSET, INFO_IMAGE_SIZE))
	info_image.name = "ToolImage"
	info_image.visible = false
	add_child(info_image)
	info_desc = GameMenuUi.make_label("", GameMenuData.text_rect_px(INFO_CENTER + INFO_DESC_OFFSET, TEXT_BOX_SIZE, INFO_DESC_MARGIN),
			GameMenuData.font_px(36), HORIZONTAL_ALIGNMENT_FILL, VERTICAL_ALIGNMENT_TOP)
	info_desc.name = "ToolDesc"
	add_child(info_desc)

## Reminder: TMP style Bold | Underline, red, centred; a RichTextLabel gives the underline.
func _build_reminder() -> void:
	reminder = RichTextLabel.new()
	reminder.name = "Reminder"
	reminder.bbcode_enabled = true
	reminder.fit_content = true
	reminder.scroll_active = false
	reminder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reminder.add_theme_font_size_override("normal_font_size", GameMenuData.font_px(42))
	reminder.add_theme_font_override("normal_font", GameMenuUi.font_for(GameMenuUi.BOLD))
	reminder.add_theme_color_override("default_color", REMINDER_COLOR)
	reminder.text = "[center][u]%s[/u][/center]" % REMINDER_TEXT
	var rect: Rect2 = GameMenuData.rect_px(REMINDER_CENTER, REMINDER_SIZE)
	reminder.position = rect.position
	reminder.size = Vector2(rect.size.x, 0.0)
	# TMP vertical alignment Middle: re-centre whenever the wrapped height changes.
	reminder.minimum_size_changed.connect(_center_reminder.bind(rect))
	add_child(reminder)
	_center_reminder.call_deferred(rect)

func _center_reminder(rect: Rect2) -> void:
	reminder.size = Vector2(rect.size.x, 0.0)
	reminder.position.y = rect.position.y + (rect.size.y - reminder.size.y) * 0.5

# --- MenuPage ---

## TalismanPage.OnEnable + ToolButton.OnEnable + the talisman holder: everything is re-read from GameState.
func page_shown() -> void:
	if not _subscribed:
		GameState.talisman_changed.connect(_refresh_all)
		_subscribed = true
	_clear_info()
	_refresh_all()
	reminder.visible = not _player_resting()

func page_hidden() -> void:
	if _subscribed:
		GameState.talisman_changed.disconnect(_refresh_all)
		_subscribed = false

## TalismanPage.SetFirstSelectedButton: the first red tool button.
func initial_focus() -> Control:
	return red_buttons[0] if not red_buttons.is_empty() else null

func _exit_tree() -> void:
	if _subscribed and GameState.talisman_changed.is_connected(_refresh_all):
		GameState.talisman_changed.disconnect(_refresh_all)
	_subscribed = false

# --- refresh (found sprites, equip state, crest) ---

func _refresh_all() -> void:
	_refresh_tool_buttons()
	_rebuild_crest()

## ToolButton.CheckIfToolFound + UpdateEquipState.
func _refresh_tool_buttons() -> void:
	for kind: int in TOOL_KINDS:
		var buttons: Array[MenuSlotButton] = _buttons(kind)
		for id in buttons.size():
			var button: MenuSlotButton = buttons[id]
			var found: bool = is_found(kind, id)
			button.icon_rect.texture = _tool_icon(kind, id) if found else _empty_tool
			button.icon_rect.modulate.a = EQUIPPED_ALPHA if is_equipped(kind, id) else 1.0

func _buttons(kind: int) -> Array[MenuSlotButton]:
	match kind:
		ToolData.ToolKind.BLUE:
			return blue_buttons
		ToolData.ToolKind.YELLOW:
			return yellow_buttons
	return red_buttons

func _found_list(kind: int) -> Array[int]:
	match kind:
		ToolData.ToolKind.BLUE:
			return GameState.found_blue_tools
		ToolData.ToolKind.YELLOW:
			return GameState.found_yellow_tools
	return GameState.found_red_tools

func _equipped_list(kind: int) -> Array[int]:
	match kind:
		ToolData.ToolKind.BLUE:
			return GameState.equipped_blue_tools
		ToolData.ToolKind.YELLOW:
			return GameState.equipped_yellow_tools
	return GameState.equipped_red_tools

func is_found(kind: int, tool_id: int) -> bool:
	return _found_list(kind).has(tool_id)

func is_equipped(kind: int, tool_id: int) -> bool:
	return _equipped_list(kind).has(tool_id)

func _tool_icon(kind: int, tool_id: int) -> Texture2D:
	return load(ToolData.tool_def(kind, tool_id)["icon"] as String) as Texture2D

## GameMaster.equippedTalisman prefab + Talisman.UpdateSlotImage: crest, slot sprites, equipped tool icons.
func _rebuild_crest() -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()
	red_slots.clear()
	blue_slots.clear()
	yellow_slots.clear()
	var talisman: int = GameState.effective_talisman()
	var layout: Dictionary = ToolData.layout(talisman)
	if String(layout["crest"]).is_empty():
		crest = null
		talisman_name_label = null
		return
	crest = GameMenuUi.make_texture(load(layout["crest"] as String) as Texture2D,
			Rect2(-CREST_SIZE * GameMenuData.CANVAS_TO_PX * 0.5, CREST_SIZE * GameMenuData.CANVAS_TO_PX))
	crest.name = "Crest"
	crest.modulate = CREST_TINT
	_holder.add_child(crest)
	var slot_kinds: Array = [["red", ToolData.RED_SLOT_ICON, red_slots, GameState.equipped_red_tools],
			["blue", ToolData.BLUE_SLOT_ICON, blue_slots, GameState.equipped_blue_tools],
			["yellow", ToolData.YELLOW_SLOT_ICON, yellow_slots, GameState.equipped_yellow_tools]]
	for kind in slot_kinds.size():
		var entry: Array = slot_kinds[kind]
		var positions: Array = layout[entry[0]]
		var equipped: Array = entry[3]
		for i in positions.size():
			var center: Vector2 = positions[i]
			var slot := GameMenuUi.make_texture(load(entry[1] as String) as Texture2D,
					Rect2(GameMenuData.to_px(center) - SLOT_SIZE * GameMenuData.CANVAS_TO_PX * 0.5, SLOT_SIZE * GameMenuData.CANVAS_TO_PX))
			slot.name = String(entry[0]).capitalize() + "Slot" + str(i)
			_holder.add_child(slot)
			(entry[2] as Array).append(slot)
			var image := GameMenuUi.make_texture(null, Rect2((SLOT_SIZE - SLOT_ICON_SIZE) * 0.5 * GameMenuData.CANVAS_TO_PX,
					SLOT_ICON_SIZE * GameMenuData.CANVAS_TO_PX))
			image.name = "Image"
			# Talisman.UpdateSlotImage: the child image is active only for slots that hold a tool.
			if i < equipped.size():
				image.texture = _tool_icon(kind, equipped[i] as int)
				image.visible = true
			else:
				image.visible = false
			slot.add_child(image)
	var name_rect: Rect2 = GameMenuData.text_rect_px(HOLDER_CENTER + TALISMAN_NAME_OFFSET, TEXT_BOX_SIZE, TALISMAN_NAME_MARGIN)
	name_rect.position -= _holder.position # the label lives under the holder, not the page
	talisman_name_label = GameMenuUi.make_label(layout["name_text"] as String, name_rect, GameMenuData.font_px(60),
			HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	talisman_name_label.name = "TalismanName"
	_holder.add_child(talisman_name_label)

# --- info box (ToolInfoBox) ---

func _clear_info() -> void:
	info_name.text = ""
	info_desc.text = ""
	info_image.texture = null
	info_image.visible = false

## ToolButton.OnSelect.
func _on_tool_selected(_slot: MenuSlotButton, kind: int, tool_id: int) -> void:
	play_moving()
	if is_found(kind, tool_id):
		var def: Dictionary = ToolData.tool_def(kind, tool_id)
		info_name.text = def["name"] as String
		info_desc.text = def["desc"] as String
		info_image.texture = _tool_icon(kind, tool_id)
		info_image.visible = true
	else:
		_clear_info()

# --- buttons ---

func _player_resting() -> bool:
	var player: Variant = menu.get("player") if menu != null else null
	return player != null and is_instance_valid(player) and bool(player.get("resting"))

func _play_pressed() -> void:
	if menu != null and menu.has_method("play_pressed"):
		menu.call("play_pressed")

## ToolButton.PressButton: only while resting, only for found tools (Unity adds the click listener only then).
func _on_tool_pressed(kind: int, tool_id: int) -> void:
	if not is_found(kind, tool_id):
		return
	if not _player_resting():
		return
	_play_pressed()
	match kind:
		ToolData.ToolKind.RED:
			GameState.equip_unequip_red_tool(tool_id)
		ToolData.ToolKind.BLUE:
			GameState.equip_unequip_blue_tool(tool_id)
		ToolData.ToolKind.YELLOW:
			GameState.equip_unequip_yellow_tool(tool_id)

## ChangeTalismanButton.PressedButton.
func _on_change_pressed() -> void:
	if not _player_resting():
		return
	_play_pressed()
	GameState.change_to_next_talisman()

func _on_change_focus_entered() -> void:
	play_moving()
	change_frame.visible = true

func _on_change_focus_exited() -> void:
	change_frame.visible = false
