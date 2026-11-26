class_name TalismanPage
extends MenuPage
## Port of the "Tools" tab (index 1): TalismanPage.cs, Talisman.cs (crest + slots), ChangeTalismanButton.cs,
## ToolButton.cs, ToolInfoBox.cs and the TalismanGroup of InventoryMenu.prefab. Equipping (tools and the
## talisman change) only works while the player rests on a chair, like Unity (`player.resting`); otherwise
## the red reminder text is shown. Blue and yellow tools can be equipped but have no gameplay (as in Unity).
##
## Layout lives in pages/talisman_page.tscn (edit it in the editor): TalismanText, ChangeTalisman button,
## ToolList (RedTools / BlueTools / YellowTools: divider bar, medal, one placed MenuSlotButton per tool),
## Bar, ToolInfoBox (ToolName, ToolImage, ToolDesc), TalismanHolder (one placed TalismanView per talisman,
## see talisman_wanderer.tscn / talisman_sentinel.tscn) and the Reminder. The script only binds data.

## ToolButton.UpdateEquipState: the icon of an equipped tool is drawn at alpha 0.3.
const EQUIPPED_ALPHA: float = 0.3
const TOOL_KINDS: Array[int] = [ToolData.ToolKind.RED, ToolData.ToolKind.BLUE, ToolData.ToolKind.YELLOW]

## Tool buttons per kind (index = ToolName value): test / navigation access.
var red_buttons: Array[MenuSlotButton] = []
var blue_buttons: Array[MenuSlotButton] = []
var yellow_buttons: Array[MenuSlotButton] = []
## Widgets of the talisman view that is shown (null when the talisman has no view).
var crest: TextureRect
var talisman_name_label: Label
## Slot rects of the shown talisman: per kind, the slot TextureRect (its child "Image" is the equipped tool).
var red_slots: Array[TextureRect] = []
var blue_slots: Array[TextureRect] = []
var yellow_slots: Array[TextureRect] = []

@onready var change_button: Button = $ChangeTalisman
@onready var change_frame: TextureRect = $ChangeTalisman/Frame
@onready var info_name: Label = $ToolInfoBox/ToolName
@onready var info_image: TextureRect = $ToolInfoBox/ToolImage
@onready var info_desc: Label = $ToolInfoBox/ToolDesc
@onready var reminder: Control = $Reminder
@onready var _holder: Control = $TalismanHolder

var _empty_tool: Texture2D
var _subscribed: bool = false

func _ready() -> void:
	_empty_tool = load(ToolData.EMPTY_TOOL_ICON) as Texture2D
	var lists: Array = [red_buttons, blue_buttons, yellow_buttons]
	var groups: Array[Node] = [$ToolList/RedTools, $ToolList/BlueTools, $ToolList/YellowTools]
	for kind: int in TOOL_KINDS:
		var id: int = 0
		for child in groups[kind].get_children():
			var button := child as MenuSlotButton
			if button == null:
				continue
			button.selected.connect(_on_tool_selected.bind(kind, id))
			button.pressed.connect(_on_tool_pressed.bind(kind, id))
			(lists[kind] as Array).append(button)
			id += 1
	change_button.focus_entered.connect(_on_change_focus_entered)
	change_button.focus_exited.connect(_on_change_focus_exited)
	change_button.mouse_entered.connect(change_button.grab_focus)
	change_button.pressed.connect(_on_change_pressed)

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
	_refresh_crest()

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

## GameMaster.equippedTalisman prefab + Talisman.UpdateSlotImage: shows the view of the equipped talisman
## (crest, slot sprites) and puts the equipped tool icons into its slots.
func _refresh_crest() -> void:
	red_slots.clear()
	blue_slots.clear()
	yellow_slots.clear()
	crest = null
	talisman_name_label = null
	var talisman: int = GameState.effective_talisman()
	var shown: TalismanView = null
	for child in _holder.get_children():
		var view := child as TalismanView
		if view == null:
			continue
		view.visible = view.talisman_id == talisman
		if view.visible:
			shown = view
	if shown == null:
		return
	crest = shown.crest
	talisman_name_label = shown.name_label
	red_slots.assign(shown.red_slots)
	blue_slots.assign(shown.blue_slots)
	yellow_slots.assign(shown.yellow_slots)
	var slot_lists: Array = [red_slots, blue_slots, yellow_slots]
	var equipped_lists: Array = [GameState.equipped_red_tools, GameState.equipped_blue_tools, GameState.equipped_yellow_tools]
	for kind in slot_lists.size():
		var slots: Array = slot_lists[kind]
		var equipped: Array = equipped_lists[kind]
		for i in slots.size():
			var image := (slots[i] as TextureRect).get_node("Image") as TextureRect
			# Talisman.UpdateSlotImage: the child image is active only for slots that hold a tool.
			if i < equipped.size():
				image.texture = _tool_icon(kind, equipped[i] as int)
				image.visible = true
			else:
				image.visible = false

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
