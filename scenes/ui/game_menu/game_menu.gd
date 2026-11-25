class_name GameMenu
extends CanvasLayer
## Port of InventoryMenu.cs + the shell of InventoryMenu.prefab: a full screen menu with four tabs
## (Inventory, Tools, Map, Journal). Opening sets `player.in_menu` (blocks gameplay input like Unity's
## inMenu) but does NOT pause the tree: enemies, physics and timers keep running.
##
## Rules (plan 13.2):
##  - `open_inventory` (I / gamepad Start) opens the Tools tab (index 1), `open_map` (Tab) the Map tab (2).
##  - `menu_tab_left` / `menu_tab_right` (Q / E, shoulder buttons) switch tabs with wrap-around.
##  - `menu_close` (I, Escape, Tab, Start, B) closes it. The event is consumed, so Escape closes this menu
##    instead of opening the pause menu; the pause menu refuses to open while this one is open (see
##    PauseMenu.can_pause) and this menu refuses to open while the tree is paused / the pause menu is open.
##  - Closed (silently) when the player gets hurt or dies; blocked while dead / hurt / during room
##    transitions and boot (Unity: Player.disableInventoryMenu).

signal opened(tab: int)
signal closed
signal tab_changed(tab: int)

## Unity: InventoryMenu.Update open branches.
const OPEN_INVENTORY_TAB: int = GameMenuData.Tab.TALISMAN
const OPEN_MAP_TAB: int = GameMenuData.Tab.MAP
## Unity: Background Image colour (0, 0, 0, 0.8627451).
const BACKGROUND_COLOR := Color(0.0, 0.0, 0.0, 0.8627451)
const TAB_UNDERLINE_COLOR := Color.WHITE

## Set by World.
var player: Player
var pause_menu: PauseMenu

var current_tab: int = 0
var pages: Array[MenuPage] = []
var inventory_page: InventoryPage
var talisman_page: TalismanPage
var map_page: MapPage
var journal_page: JournalPage
var tab_labels: Array[Label] = []

var _open: bool = false
var _closed_frame: int = -1
var _tab_underline: ColorRect
var _focus_generation: int = 0

@onready var _open_sfx: AudioStreamPlayer = $Sfx/OpenInventory
@onready var _close_sfx: AudioStreamPlayer = $Sfx/CloseInventory
@onready var _moving_sfx: AudioStreamPlayer = $Sfx/Moving
@onready var _pressed_sfx: AudioStreamPlayer = $Sfx/Pressed

func _ready() -> void:
	visible = false
	var holder := Control.new()
	holder.name = "Holder"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(background)

	# Pages in tab order.
	inventory_page = InventoryPage.new()
	inventory_page.name = "InventoryGroup"
	talisman_page = TalismanPage.new()
	talisman_page.name = "TalismanGroup"
	map_page = MapPage.new()
	map_page.name = "MapGroup"
	journal_page = JournalPage.new()
	journal_page.name = "JournalGroup"
	pages = [inventory_page, talisman_page, map_page, journal_page]
	for page: MenuPage in pages:
		page.menu = self
		page.visible = false
		holder.add_child(page)

	# MenuTab header (on top of every page, like the prefab's last child of each group).
	var tab_bar := Control.new()
	tab_bar.name = "MenuTab"
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tab_bar)
	for i in GameMenuData.TAB_NAMES.size():
		var center := Vector2(GameMenuData.TAB_BAR_LEFT + GameMenuData.TAB_BOX_SIZE.x * 0.5 + i * GameMenuData.TAB_STEP,
				GameMenuData.TAB_BAR_TOP - GameMenuData.TAB_BOX_SIZE.y * 0.5)
		var label := GameMenuUi.make_label(GameMenuData.TAB_NAMES[i], GameMenuData.rect_px(center, GameMenuData.TAB_BOX_SIZE),
				GameMenuData.font_px(GameMenuData.TAB_FONT_OTHER), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0, false)
		label.name = GameMenuData.TAB_NAMES[i]
		tab_bar.add_child(label)
		tab_labels.append(label)
	_tab_underline = GameMenuUi.make_rect(Rect2(), TAB_UNDERLINE_COLOR)
	_tab_underline.name = "Underline"
	tab_bar.add_child(_tab_underline)

func _exit_tree() -> void:
	# The world was freed while open: never leave the player flagged.
	if _open and player != null and is_instance_valid(player):
		player.in_menu = false
	_open = false

func is_open() -> bool:
	return _open

## True for the frame the menu was closed in as well (a same-frame Escape must not open the pause menu).
func blocks_pause() -> bool:
	return _open or _closed_frame == Engine.get_process_frames()

## InventoryMenu.Update guards: not already open, and not while dead / hurt / in a transition / paused.
func can_open() -> bool:
	if _open or player == null or not is_instance_valid(player):
		return false
	var tree := get_tree()
	if tree == null or tree.paused:
		return false
	if pause_menu != null and is_instance_valid(pause_menu) and pause_menu.is_open():
		return false
	return not player.is_dead and not player.is_hurt and not RoomLoader.is_transitioning()

## Opens on `tab` (an index of GameMenuData.Tab). Returns false if blocked.
func open(tab: int) -> bool:
	if not can_open():
		return false
	_open = true
	player.in_menu = true
	visible = true
	_open_sfx.play()
	_show_tab(tab)
	opened.emit(tab)
	return true

## Closes the menu. `silent` skips the close sound (Unity's CloseMenu on hurt).
func close(silent: bool = false) -> void:
	if not _open:
		return
	_open = false
	_closed_frame = Engine.get_process_frames()
	_focus_generation += 1
	if current_tab >= 0 and current_tab < pages.size():
		pages[current_tab].page_hidden()
		pages[current_tab].visible = false
	visible = false
	if player != null and is_instance_valid(player):
		player.in_menu = false
		# The key that closed the menu (Q, B, ...) must not trigger a gameplay action on the same tick.
		player.swallow_input_edges()
	if not silent:
		_close_sfx.play()
	closed.emit()

## LeftTab / RightTab: `direction` -1 / +1, wraps.
func switch_tab(direction: int) -> void:
	if not _open:
		return
	_show_tab(posmod(current_tab + direction, pages.size()))
	_open_sfx.play()

func play_moving() -> void:
	_moving_sfx.play()

func play_pressed() -> void:
	_pressed_sfx.play()

## InventoryMenu.UpdateInventoryMenuTab.
func _show_tab(tab: int) -> void:
	tab = clampi(tab, 0, pages.size() - 1)
	if current_tab >= 0 and current_tab < pages.size() and pages[current_tab].visible:
		pages[current_tab].page_hidden()
		pages[current_tab].visible = false
	current_tab = tab
	var page: MenuPage = pages[tab]
	page.visible = true
	page.page_shown()
	_update_tab_bar()
	_focus_generation += 1
	_focus_initial.call_deferred(_focus_generation)
	tab_changed.emit(tab)

func _update_tab_bar() -> void:
	for i in tab_labels.size():
		var label: Label = tab_labels[i]
		var current: bool = i == current_tab
		var px: int = GameMenuData.font_px(GameMenuData.TAB_FONT_CURRENT if current else GameMenuData.TAB_FONT_OTHER)
		label.add_theme_font_size_override("font_size", px)
		label.add_theme_font_override("font", GameMenuUi.font_for(GameMenuUi.BOLD if current else 0))
	# Underline of the current tab (TMP font style Bold | Underline).
	var cur: Label = tab_labels[current_tab]
	var font: Font = cur.get_theme_font("font")
	var px_size: int = cur.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(cur.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px_size).x
	var base_y: float = cur.position.y + cur.size.y * 0.5 + font.get_ascent(px_size) * 0.5 + 1.0
	_tab_underline.position = Vector2(cur.position.x + (cur.size.x - text_w) * 0.5, base_y)
	_tab_underline.size = Vector2(text_w, 1.0)

## JournalPage / InventoryPage.SetFirstSelectedButton (Unity waits 0.01 s, one frame here).
func _focus_initial(generation: int) -> void:
	if not _open or generation != _focus_generation:
		return
	var target: Control = pages[current_tab].initial_focus()
	if target != null and target.is_inside_tree() and target.is_visible_in_tree():
		target.grab_focus()
	else:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()

func _process(_delta: float) -> void:
	if not _open:
		return
	# Unity: `if (player.isHurt) CloseMenu();` every frame. Death and room transitions close it too.
	if player == null or not is_instance_valid(player) or player.is_hurt or player.is_dead or RoomLoader.is_transitioning():
		close(true)

func _input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed(&"open_inventory", false):
			if open(OPEN_INVENTORY_TAB):
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"open_map", false):
			if open(OPEN_MAP_TAB):
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"menu_close", false):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"menu_tab_left", false):
		switch_tab(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"menu_tab_right", false):
		switch_tab(1)
		get_viewport().set_input_as_handled()
