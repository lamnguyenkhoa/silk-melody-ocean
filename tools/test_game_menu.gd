extends SceneTree
## Automated game menu test (plan 13, phase M1): open / close / tab wrap / map key / hurt closes / blocked
## in transitions and death / in_menu blocks movement / interaction with the pause menu / inventory, map and
## journal contents / save round trip of the new fields and loading an old-format save. Real world scene,
## input injected as real key / joypad events.
## Run: godot --headless --path . -s tools/test_game_menu.gd
## Any existing user save is backed up and restored; the test works on its own temporary saves.

const WORLD_PATH := "res://scenes/world/world.tscn"
const SAVE_FILES: Array[String] = ["user://player.json", "user://world.json"]
const MAX_WAIT_FRAMES := 900
## RoomLoader.StartMode (autoload identifiers are not available to -s scripts).
const NEW_GAME := 0
## Tab indices (GameMenuData.Tab) and item / enemy ids (InventoryIds), as plain ints for -s compile order.
const TAB_INVENTORY := 0
const TAB_TALISMAN := 1
const TAB_MAP := 2
const TAB_JOURNAL := 3
const ITEM_VERDANT := 0
const ITEM_SPOOL := 1
const ITEM_MASK := 2
const ITEM_NEEDLE := 3
const ITEM_COOL_KEY := 4
const ITEM_NOTEBOOK := 5
const ITEM_BACKPACK := 6
const ITEM_SANDAL := 7
const NEW_FIELDS: Array[String] = ["inventory_item_amount", "found_talismans", "equipped_talisman", "red_tools_current_charge",
		"found_red_tools", "equipped_red_tools", "selected_red_tool_id", "found_blue_tools", "equipped_blue_tools",
		"found_yellow_tools", "equipped_yellow_tools"]

var gs
var rl
var world
var player
var gm
var pm
var rows: Array = []
var fails: int = 0
var _backup: Dictionary = {}


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rl = root.get_node("RoomLoader")
	_backup_saves()
	gs.delete_save()

	_test_new_game_data()
	await _boot_world()
	await _test_open_close()
	await _test_tabs()
	await _test_escape_and_pause()
	await _test_gamepad_start()
	await _test_hurt_closes()
	await _test_blocked()
	await _test_in_menu_blocks_gameplay()
	await _test_menu_close_swallows_silk_skill()
	await _test_inventory()
	await _test_map()
	await _test_journal()
	await _test_enemy_type_mapping()
	_test_talisman_placeholder()
	_test_save_roundtrip()
	_test_old_save()
	_test_debug_inventory()
	await _test_cleanup()

	if world != null and is_instance_valid(world):
		world.free()
	paused = false
	Engine.time_scale = 1.0
	await process_frame
	_restore_saves()
	_print_table()
	quit(1 if fails > 0 else 0)


# --- helpers ---

func _backup_saves() -> void:
	for p in SAVE_FILES:
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)

func _restore_saves() -> void:
	gs.delete_save()
	for p in _backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(_backup[p])
		f.close()

func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1

func _check(name: String, ok: bool, note: String = "") -> void:
	_add(name, str(ok), "true", ok, note)

func _eq(name: String, measured, expected) -> void:
	_add(name, str(measured), str(expected), measured == expected)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _until(cond: Callable, max_frames: int = MAX_WAIT_FRAMES) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _act(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _press(action: StringName) -> void:
	_act(action, true)
	await process_frame
	_act(action, false)
	await process_frame

func _send_key(keycode: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _key(keycode: Key) -> void:
	_send_key(keycode, true)
	await process_frame
	_send_key(keycode, false)
	await process_frame

func _send_pad(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _pad(button: JoyButton) -> void:
	_send_pad(button, true)
	await process_frame
	_send_pad(button, false)
	await process_frame

func _focus_name() -> String:
	var f := root.gui_get_focus_owner()
	return f.name if f != null else "<none>"

func _boot_world() -> void:
	if world != null and is_instance_valid(world):
		world.free()
		await process_frame
	gs.reset_to_new_game()
	world = (load(WORLD_PATH) as PackedScene).instantiate()
	world.spawn_debug_dummies = false
	world.set("start_mode", NEW_GAME)
	root.add_child(world)
	current_scene = world
	player = world.get_node("Player")
	gm = world.get_node("GameMenu")
	pm = world.get_node("PauseMenu")
	await _until(func(): return not rl.is_transitioning())
	await _until(func(): return player.is_on_floor(), 600)
	await _frames(5)

func _ensure_closed() -> void:
	if gm.is_open():
		gm.close(true)
	if pm.is_open():
		pm.close()
	await _frames(2)


# --- tests ---

func _test_new_game_data() -> void:
	gs.reset_to_new_game()
	_eq("new game: item amounts (mantle spool mask needle key notebook backpack sandal)", gs.inventory_item_amount, [1, 1, 1, 1, 0, 1, 1, 0])
	_eq("new game: found talismans [wanderer]", gs.found_talismans, [0])
	_eq("new game: equipped talisman wanderer", gs.equipped_talisman, 0)
	_eq("new game: red tool charges = maxCharge", gs.red_tools_current_charge, [10.0, 5.0, 2.0])
	_eq("new game: no tools found / equipped", [gs.found_red_tools, gs.equipped_red_tools, gs.found_blue_tools, gs.equipped_blue_tools, gs.found_yellow_tools, gs.equipped_yellow_tools], [[], [], [], [], [], []])
	_eq("new game: selected red tool 0", gs.selected_red_tool_id, 0)

func _test_open_close() -> void:
	_check("open/close: closed at start", not gm.is_open() and not gm.visible and not player.in_menu)
	await _key(KEY_I)
	_check("open: I opens the menu", gm.is_open() and gm.visible)
	_eq("open: I -> Talisman (tools) tab index 1", gm.current_tab, TAB_TALISMAN)
	_check("open: player.in_menu set", player.in_menu)
	_check("open: tree not paused, time_scale untouched", not paused and Engine.time_scale == 1.0)
	_eq("open: control_lock untouched (flag, not lock)", player.control_lock, 0)
	_check("open: only the talisman page visible", gm.pages[TAB_TALISMAN].visible and not gm.pages[TAB_INVENTORY].visible and not gm.pages[TAB_MAP].visible and not gm.pages[TAB_JOURNAL].visible)
	_check("open: sound played", gm.get_node("Sfx/OpenInventory").playing)
	await _key(KEY_I)
	_check("close: I closes the menu", not gm.is_open() and not gm.visible)
	_check("close: player.in_menu cleared", not player.in_menu)
	await _key(KEY_I)
	_check("reopen after close", gm.is_open())
	await _key(KEY_TAB)
	_check("close: Tab closes (Inventory.OutOfMenu)", not gm.is_open())
	# Map key
	await _key(KEY_TAB)
	_check("map key: Tab opens", gm.is_open())
	_eq("map key: Tab -> Map tab index 2", gm.current_tab, TAB_MAP)
	_check("map key: map page visible, others hidden", gm.pages[TAB_MAP].visible and not gm.pages[TAB_TALISMAN].visible)
	await _key(KEY_I)
	_check("map key: I closes from the map tab", not gm.is_open())
	_check("open: refuses a second open call while open", (func() -> bool:
		gm.open(TAB_MAP)
		return not gm.open(TAB_JOURNAL) and gm.current_tab == TAB_MAP).call())
	await _ensure_closed()

func _test_tabs() -> void:
	await _ensure_closed()
	await _key(KEY_I)
	_eq("tabs: start on Tools (1)", gm.current_tab, TAB_TALISMAN)
	await _key(KEY_E)
	_eq("tabs: E -> Map (2)", gm.current_tab, TAB_MAP)
	await _key(KEY_E)
	_eq("tabs: E -> Journal (3)", gm.current_tab, TAB_JOURNAL)
	await _key(KEY_E)
	_eq("tabs: E wraps -> Inventory (0)", gm.current_tab, TAB_INVENTORY)
	await _key(KEY_Q)
	_eq("tabs: Q wraps -> Journal (3)", gm.current_tab, TAB_JOURNAL)
	await _key(KEY_Q)
	_eq("tabs: Q -> Map (2)", gm.current_tab, TAB_MAP)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_eq("tabs: right shoulder -> Journal (3)", gm.current_tab, TAB_JOURNAL)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_eq("tabs: left shoulder -> Map (2)", gm.current_tab, TAB_MAP)
	var visible_pages := 0
	for p in gm.pages:
		if p.visible:
			visible_pages += 1
	_eq("tabs: exactly one page visible", visible_pages, 1)
	var label_sizes: Array = []
	for l in gm.tab_labels:
		label_sizes.append(l.get_theme_font_size("font_size"))
	_eq("tabs: current tab header larger (Map 10 px, others 8 px)", label_sizes, [8, 8, 10, 8])
	_eq("tabs: header texts", gm.tab_labels.map(func(l): return l.text), ["Inventory", "Tools", "Map", "Journal"])
	_check("tabs: Q/E do nothing while closed", await (func() -> bool:
		await _ensure_closed()
		await _key(KEY_E)
		return not gm.is_open()).call())
	await _ensure_closed()

func _test_escape_and_pause() -> void:
	await _ensure_closed()
	# Escape with the game menu closed -> pause menu.
	await _key(KEY_ESCAPE)
	_check("pause: Escape opens the pause menu (menu closed)", pm.is_open() and paused)
	await _key(KEY_I)
	_check("pause: game menu refuses to open while paused", not gm.is_open() and not player.in_menu)
	await _key(KEY_TAB)
	_check("pause: Tab (map) refused while paused", not gm.is_open())
	_check("pause: open() returns false while the pause menu is open", not gm.open(TAB_MAP))
	await _key(KEY_ESCAPE)
	_check("pause: Escape closes the pause menu", not pm.is_open() and not paused)
	# Escape with the game menu open -> closes the game menu, does NOT open pause.
	await _key(KEY_I)
	_check("escape: game menu open", gm.is_open())
	await _key(KEY_ESCAPE)
	_check("escape: closes the game menu", not gm.is_open() and not player.in_menu)
	_check("escape: pause menu NOT opened, tree not paused", not pm.is_open() and not paused)
	await _key(KEY_ESCAPE)
	_check("escape: next Escape opens pause", pm.is_open() and paused)
	await _key(KEY_ESCAPE)
	_check("escape: and closes it", not pm.is_open() and not paused)
	# Pause menu cannot open while the game menu is open (gamepad Back = pause).
	await _key(KEY_I)
	await _pad(JOY_BUTTON_BACK)
	_check("pause: gamepad Back refused while the game menu is open", gm.is_open() and not pm.is_open() and not paused)
	_check("pause: PauseMenu.open() refused while the game menu is open", not pm.open())
	_check("pause: can_pause false while the game menu is open", not pm.can_pause())
	await _ensure_closed()

func _test_gamepad_start() -> void:
	await _ensure_closed()
	await _pad(JOY_BUTTON_START)
	_check("gamepad: Start opens the game menu (Unity InventoryMenu), not pause", gm.is_open() and not pm.is_open() and not paused)
	_eq("gamepad: Start -> Tools tab", gm.current_tab, TAB_TALISMAN)
	await _pad(JOY_BUTTON_START)
	_check("gamepad: Start closes it again (OutOfMenu)", not gm.is_open())
	await _pad(JOY_BUTTON_START)
	await _pad(JOY_BUTTON_B)
	_check("gamepad: B closes it", not gm.is_open())
	await _pad(JOY_BUTTON_BACK)
	_check("gamepad: Back (select) opens pause", pm.is_open() and paused)
	await _pad(JOY_BUTTON_BACK)
	_check("gamepad: Back closes pause", not pm.is_open())
	await _ensure_closed()

func _test_hurt_closes() -> void:
	await _ensure_closed()
	await _key(KEY_TAB)
	_check("hurt: menu open", gm.is_open() and player.in_menu)
	var hp: int = gs.current_hp
	gm.get_node("Sfx/CloseInventory").stop()
	player.damaged(1, Vector2.LEFT)
	_check("hurt: damage taken (hp -1)", gs.current_hp == hp - 1)
	_check("hurt: is_hurt set", player.is_hurt)
	await _frames(3)
	_check("hurt: menu closed by getting hurt", not gm.is_open() and not gm.visible)
	_check("hurt: in_menu cleared", not player.in_menu)
	_check("hurt: closing was silent (no close sound)", not gm.get_node("Sfx/CloseInventory").playing)
	await _key(KEY_I)
	_check("hurt: cannot open while hurt", not gm.is_open())
	await _until(func(): return not player.is_hurt and Engine.time_scale == 1.0, 600)
	await _frames(5)
	await _key(KEY_I)
	_check("hurt: can open again once the stun is over", gm.is_open())
	await _ensure_closed()
	await _until(func(): return not player.in_i_frame, 600)

func _test_blocked() -> void:
	await _ensure_closed()
	# during a room transition
	rl.load_level("DirtCave0", "")
	await _frames(3)
	_check("blocked: transition running", rl.is_transitioning())
	await _key(KEY_I)
	_check("blocked: I refused during a room transition", not gm.is_open() and not player.in_menu)
	await _key(KEY_TAB)
	_check("blocked: Tab refused during a room transition", not gm.is_open())
	await _until(func(): return not rl.is_transitioning())
	await _frames(5)
	await _key(KEY_I)
	_check("blocked: opens after the transition", gm.is_open())
	# open menu then transition starts -> closes
	rl.load_level("DirtCave0", "")
	await _frames(3)
	_check("blocked: open menu closed when a transition starts", not gm.is_open() and not player.in_menu)
	await _until(func(): return not rl.is_transitioning())
	await _frames(5)
	await _until(func(): return player.is_on_floor(), 600)
	# dead
	player.is_dead = true
	await _key(KEY_I)
	_check("blocked: refused while dead", not gm.is_open())
	player.is_dead = false
	# real death closes it
	await _key(KEY_I)
	_check("blocked: opened before death", gm.is_open())
	player.damaged(99, Vector2.LEFT)
	await _frames(3)
	_check("blocked: death closes the menu", not gm.is_open() and not player.in_menu)
	var opened_during := false
	for i in 12:
		await _key(KEY_I)
		opened_during = opened_during or gm.is_open()
		if gm.is_open():
			gm.close(true)
		await _frames(5)
	_check("blocked: never opens during death / respawn", not opened_during)
	await _until(func(): return not player.is_dead and not rl.is_transitioning(), 900)
	await _until(func(): return player.is_on_floor(), 900)
	await _frames(10)
	_eq("blocked: control lock back to 0 after respawn", player.control_lock, 0)
	await _key(KEY_I)
	_check("blocked: opens after the respawn", gm.is_open())
	await _ensure_closed()

func _test_in_menu_blocks_gameplay() -> void:
	await _ensure_closed()
	await _until(func(): return player.is_on_floor(), 600)
	await _frames(30)
	player.velocity = Vector2.ZERO
	var x0: float = player.global_position.x
	await _key(KEY_I)
	_act(&"move_right", true)
	await _frames(40)
	var x1: float = player.global_position.x
	_check("in_menu: move_right does not move the player (%.2f -> %.2f)" % [x0, x1], absf(x1 - x0) < 0.5)
	await _press(&"jump")
	await _frames(10)
	_check("in_menu: jump does nothing (still on the floor, vy %.1f)" % player.velocity.y, player.is_on_floor() and player.velocity.y > -1.0)
	await _press(&"attack")
	await _frames(3)
	_check("in_menu: attack does nothing", not player.in_attack)
	_act(&"move_right", false)
	await _key(KEY_I)
	_check("in_menu: closed", not gm.is_open() and not player.in_menu)
	var x2: float = player.global_position.x
	_act(&"move_right", true)
	await _frames(30)
	_act(&"move_right", false)
	_check("in_menu: after closing the player moves again (%.2f -> %.2f)" % [x2, player.global_position.x], player.global_position.x - x2 > 10.0)
	await _frames(30)
	# the world keeps running while the menu is open: a falling player keeps falling
	player.global_position.y -= 90.0
	player.velocity = Vector2.ZERO
	await _frames(2)
	var y0: float = player.global_position.y
	await _key(KEY_I)
	var frames0: int = Engine.get_physics_frames()
	await _frames(15)
	_check("in_menu: physics keeps running (frames advanced, player fell %.1f px)" % (player.global_position.y - y0),
			Engine.get_physics_frames() > frames0 + 5 and player.global_position.y > y0 + 3.0 and not paused and Engine.time_scale == 1.0)
	await _until(func(): return player.is_on_floor(), 300)
	_check("in_menu: gravity landed the player while in the menu", player.is_on_floor() and gm.is_open())
	await _ensure_closed()

func _test_menu_close_swallows_silk_skill() -> void:
	await _ensure_closed()
	await _until(func(): return player.is_on_floor(), 600)
	gs.current_silk = gs.max_silk
	gs.current_hp = gs.max_hp - 2
	gs.stats_changed.emit()
	await _key(KEY_I)
	# Gamepad B closes the menu AND is the silk skill button: it must only close.
	_send_pad(JOY_BUTTON_B, true)
	await _frames(3)
	_send_pad(JOY_BUTTON_B, false)
	await _frames(20)
	_check("close key: B closed the menu", not gm.is_open())
	_check("close key: B did not trigger the heal (silk %d, skill lock %s)" % [gs.current_silk, player.in_silk_skill], gs.current_silk == gs.max_silk and not player.in_silk_skill)
	gs.current_hp = gs.max_hp
	gs.current_silk = 0
	gs.stats_changed.emit()
	await _ensure_closed()

func _test_inventory() -> void:
	await _ensure_closed()
	gs.reset_to_new_game()
	gm.open(TAB_INVENTORY)
	await _frames(4)
	var page = gm.inventory_page
	_check("inventory: opened on tab 0 with the inventory page", gm.current_tab == TAB_INVENTORY and page.visible)
	_eq("inventory: static slots (needle, mask, spool)", [page.static_slots.has(ITEM_NEEDLE), page.static_slots.has(ITEM_MASK), page.static_slots.has(ITEM_SPOOL)], [true, true, true])
	var grid_names: Array = page.grid_slots.map(func(s): return str(s.name))
	_eq("inventory: grid shows the new-game items in Unity order", grid_names, ["VerdantMantle", "NotebookandQuill", "CarapaceBackpack"])
	_check("inventory: no Cool Key / Silkbind Sandal (amount 0)", not grid_names.has("CoolKey") and not grid_names.has("SilkbindSandal"))
	_eq("inventory: Mask has the initial focus", _focus_name(), "Mask")
	_check("inventory: focused slot shows its select frame only", page.static_slots[ITEM_MASK].is_frame_visible() and not page.static_slots[ITEM_SPOOL].is_frame_visible() and not page.grid_slots[0].is_frame_visible())
	_eq("inventory: info name = Mask", page.name_label.text, "Mask")
	_eq("inventory: info description", page.desc_label.text, "More masks equals more health. Go collect more masks for a healthier life.")
	await _press(&"ui_down")
	_eq("inventory: ui_down -> Silk Spool", _focus_name(), "SilkSpool")
	_eq("inventory: info follows the focus (Silk Spool)", page.name_label.text, "Silk Spool")
	await _press(&"ui_up")
	_eq("inventory: ui_up back to Mask", _focus_name(), "Mask")
	await _press(&"ui_right")
	var f := root.gui_get_focus_owner()
	_check("inventory: ui_right moves focus to another slot (%s)" % _focus_name(), f != null and f != page.static_slots[ITEM_MASK] and f is MenuSlotButton)
	_eq("inventory: info name matches the focused slot", page.name_label.text, GameMenuDataName(f.item_id))
	# Extra items show up (rebuilt on show), Cool Key shows its amount.
	gm.switch_tab(1)
	gs.inventory_item_amount[ITEM_COOL_KEY] = 3
	gs.inventory_item_amount[ITEM_SANDAL] = 1
	gm.switch_tab(-1)
	await _frames(3)
	grid_names = page.grid_slots.map(func(s): return str(s.name))
	_eq("inventory: grid order with all items", grid_names, ["VerdantMantle", "NotebookandQuill", "CarapaceBackpack", "SilkbindSandal", "CoolKey"])
	var key_slot = page.grid_slots[4]
	_check("inventory: Cool Key shows 'x3' amount (amount > 1)", key_slot.amount_label != null and key_slot.amount_label.text == "3")
	_check("inventory: Verdant Mantle has no amount label", page.grid_slots[0].amount_label == null)
	_eq("inventory: grid is 5 columns, first row y equal", page.grid_slots[0].position.y == page.grid_slots[4].position.y, true)
	# Slots are destroyed when the tab is hidden (Unity OnDisable).
	gm.switch_tab(1)
	await _frames(2)
	_eq("inventory: grid emptied when the tab is hidden", page.grid_slots.size(), 0)
	await _ensure_closed()
	gs.reset_to_new_game()

func GameMenuDataName(item: int) -> String:
	return ["Verdant Mantle", "Silk Spool", "Mask", "Needle", "Cool Key", "Notebook and Quill", "Carapace Backpack", "Silkbind Sandal"][item]

func _test_map() -> void:
	await _ensure_closed()
	gs.reset_to_new_game()
	gs.add_visited_room("DirtCave0")
	gm.open(TAB_MAP)
	await _frames(3)
	var page = gm.map_page
	var visible_rooms: Array = []
	for n in page.room_nodes:
		if page.room_nodes[n].visible:
			visible_rooms.append(str(n))
	_eq("map: only visited rooms shown", visible_rooms, ["DirtCave0"])
	var visible_paths: Array = page.path_nodes.filter(func(p): return p.visible).map(func(p): return str(p.name))
	_eq("map: paths shown when either room visited (0 1 only)", visible_paths, ["0 1"])
	_eq("map: 16 rooms and 16 paths ported", [page.room_nodes.size(), page.path_nodes.size()], [16, 16])
	_check("map: player marker on the current room", page.marker != null and page.marker.get_parent() == page.room_nodes["DirtCave0"])
	var center: Vector2 = page.room_nodes["DirtCave0"].get_global_rect().get_center()
	_check("map: content centred on the current room (%s)" % center, center.distance_to(Vector2(192, 108)) < 0.5)
	_eq("map: opened at scale 1", page.content.scale, Vector2.ONE)
	# more rooms visited, other current room
	gs.add_visited_room("DirtCave1")
	gs.add_visited_room("DirtCave2")
	gs.add_visited_room("DirtCave3")
	page.page_shown()
	visible_rooms = []
	for n in page.room_nodes:
		if page.room_nodes[n].visible:
			visible_rooms.append(str(n))
	_eq("map: rooms after visiting 1-3", visible_rooms, ["DirtCave0", "DirtCave1", "DirtCave2", "DirtCave3"])
	visible_paths = page.path_nodes.filter(func(p): return p.visible).map(func(p): return str(p.name))
	_eq("map: paths after visiting 1-3 (0 1, 1 2, 2 3, 2 4, 2 14)", visible_paths, ["0 1", "1 2", "2 3", "2 4", "2 14"])
	_check("map: DirtCave3 rest chair icon child visible with its room", page.room_nodes["DirtCave3"].get_child_count() >= 1 and page.room_nodes["DirtCave3"].get_child(0).is_visible_in_tree())
	_check("map: unvisited DirtCave8 chair icon hidden with its room", not page.room_nodes["DirtCave8"].get_child(0).is_visible_in_tree())
	_check("map: update_player_pos on DirtCave3", page.update_player_pos("DirtCave3") and page.marker.get_parent() == page.room_nodes["DirtCave3"])
	center = page.room_nodes["DirtCave3"].get_global_rect().get_center()
	_check("map: centred on DirtCave3 (%s)" % center, center.distance_to(Vector2(192, 108)) < 0.5)
	_check("map: unknown scene -> no marker, content untouched", not page.update_player_pos("Nowhere") and page.marker == null)
	page.update_player_pos("DirtCave0")
	# pan / zoom clamps
	page.content.scale = Vector2.ONE
	var pos0: Vector2 = page.content.position
	page.step(Vector2(1, 0), 0.0, 0.1)
	_check("map: pan right moves the content left by 1000/5*0.1 = 20 px (%s)" % (page.content.position - pos0), (page.content.position - pos0).is_equal_approx(Vector2(-20, 0)))
	page.step(Vector2(0, -1), 0.0, 0.1)
	_check("map: pan up (W) moves the content down", (page.content.position - pos0).y > 19.9)
	page.step(Vector2.ZERO, 1.0, 0.5)
	_check("map: zoom in +0.5 -> scale 1.5", is_equal_approx(page.content.scale.x, 1.5))
	page.step(Vector2.ZERO, 1.0, 100.0)
	_eq("map: zoom in clamps at 3", page.content.scale.x, 3.0)
	page.step(Vector2.ZERO, -1.0, 100.0)
	_check("map: zoom out clamps at 0.2", is_equal_approx(page.content.scale.x, 0.2))
	_check("map: scale stays uniform", page.content.scale.x == page.content.scale.y)
	# real input
	page.content.scale = Vector2.ONE
	Input.action_press(&"map_zoom_in", 1.0)
	await _frames(20)
	Input.action_release(&"map_zoom_in")
	_check("map: real zoom-in input grows the scale (%.2f)" % page.content.scale.x, page.content.scale.x > 1.02 and page.content.scale.x <= 3.0)
	var p1: Vector2 = page.content.position
	Input.action_press(&"map_pan_right", 1.0)
	await _frames(20)
	Input.action_release(&"map_pan_right")
	_check("map: real pan input moves the content (%s)" % (page.content.position - p1), page.content.position.x < p1.x - 5.0)
	# leaving and re-entering resets
	gm.switch_tab(1)
	_check("map: marker removed when the tab is hidden", page.marker == null)
	gm.switch_tab(-1)
	_eq("map: scale reset to 1 on re-entry", page.content.scale, Vector2.ONE)
	center = page.room_nodes[rl.current_room_name].get_global_rect().get_center()
	_check("map: re-centred on the current room (%s, %s)" % [rl.current_room_name, center], center.distance_to(Vector2(192, 108)) < 0.5)
	await _ensure_closed()
	gs.reset_to_new_game()

func _test_journal() -> void:
	await _ensure_closed()
	gs.reset_to_new_game()
	gm.open(TAB_JOURNAL)
	await _frames(4)
	var page = gm.journal_page
	_eq("journal: 8 lore rows in EnemyType order", page.rows.map(func(r): return str(r.name)),
			["Crawling", "Dipsa", "TwistedDipsa", "Crabber", "LapisLazer", "BeetleBatter", "Batter'sContraption", "GreatCrawler"])
	_eq("journal: all rows '???' with 0 kills", page.rows.map(func(r): return r.text), ["???", "???", "???", "???", "???", "???", "???", "???"])
	_eq("journal: first row focused", _focus_name(), "Crawling")
	_eq("journal: undiscovered -> 'Defeated: 0'", page.kill_label.text, "Defeated: 0")
	_check("journal: undiscovered -> black silhouette", page.enemy_image.modulate == Color.BLACK and page.enemy_image.texture != null)
	_check("journal: undiscovered -> empty name / description / flavour", page.name_label.text == "" and page.desc_label.text == "" and page.flavor_label.text == "")
	# Native size of the Crawling sprite: 74x42 px at PPU 64 -> 115.625 x 65.625 canvas units -> /5
	_check("journal: enemy image native size (23.1 x 13.1 px)", page.enemy_image.size.is_equal_approx(Vector2(115.625, 65.625) * 0.2))
	_check("journal: selected row centred in the list", is_equal_approx(page.rows[0].get_global_rect().get_center().y, page.get_node("EnemyList").get_global_rect().get_center().y))
	# discovered enemies
	gs.world.enemy_kill_count = {0: 5, 1: 2, 3: 1}
	gm.switch_tab(1)
	gm.switch_tab(-1)
	await _frames(3)
	_eq("journal: names for discovered, ??? for the rest", page.rows.map(func(r): return r.text),
			["Crawling", "Dipsa", "???", "Crabber", "???", "???", "???", "???"])
	_eq("journal: focus is remembered on re-entry (row 0)", _focus_name(), "Crawling")
	_eq("journal: Crawling name", page.name_label.text, "Crawling")
	_eq("journal: Crawling kills", page.kill_label.text, "Defeated: 5")
	_eq("journal: Crawling description", page.desc_label.text, "It just walk.")
	_eq("journal: Crawling flavour", page.flavor_label.text, "Very useless and easy to kill.")
	_check("journal: discovered -> normal colours", page.enemy_image.modulate == Color.WHITE)
	await _press(&"ui_down")
	_eq("journal: ui_down -> Dipsa", _focus_name(), "Dipsa")
	_eq("journal: Dipsa kills", page.kill_label.text, "Defeated: 2")
	_eq("journal: Dipsa description", page.desc_label.text, "Shoot orange bullet at you.")
	_check("journal: scrolled so Dipsa is centred", is_equal_approx(page.rows[1].get_global_rect().get_center().y, page.get_node("EnemyList").get_global_rect().get_center().y))
	await _press(&"ui_down")
	_eq("journal: ui_down -> Twisted Dipsa (undiscovered)", _focus_name(), "TwistedDipsa")
	_eq("journal: undiscovered shows 'Defeated: 0'", page.kill_label.text, "Defeated: 0")
	_check("journal: undiscovered silhouette again, text cleared", page.enemy_image.modulate == Color.BLACK and page.name_label.text == "" and page.desc_label.text == "")
	for i in 5:
		await _press(&"ui_down")
	_eq("journal: ui_down reaches the last row", _focus_name(), "GreatCrawler")
	await _press(&"ui_down")
	_check("journal: focus stays inside the list at the end", page.rows.has(root.gui_get_focus_owner()))
	# leave and come back: last selected row
	await _key(KEY_I)
	_check("journal: closed", not gm.is_open())
	gm.open(TAB_JOURNAL)
	await _frames(4)
	_eq("journal: last selected row remembered after closing", _focus_name(), "GreatCrawler")
	await _ensure_closed()
	gs.reset_to_new_game()

func _test_enemy_type_mapping() -> void:
	var map := {"res://scenes/enemies/crawling.tscn": 0, "res://scenes/enemies/dipsa.tscn": 1, "res://scenes/enemies/crabber.tscn": 3}
	for path in map:
		var e = (load(path) as PackedScene).instantiate()
		_eq("enemy_type mapping: %s -> EnemyLore.EnemyType %d" % [path.get_file(), map[path]], e.enemy_type, map[path])
		e.free()
	# a kill increments the key the journal reads
	gs.reset_to_new_game()
	var d = (load("res://scenes/enemies/dipsa.tscn") as PackedScene).instantiate()
	world.add_child(d)
	d.global_position = player.global_position + Vector2(300, -100)
	await _frames(2)
	d.damaged(999, Vector2.RIGHT)
	await _frames(3)
	_eq("enemy_type mapping: killing a Dipsa counts for journal row 'Dipsa' (type 1)", gs.get_kill_count(1), 1)
	d.queue_free()
	gs.reset_to_new_game()

func _test_talisman_placeholder() -> void:
	_eq("talisman: Talisman page in slot 1 (M2, tests in test_tools.gd)", gm.pages[TAB_TALISMAN].get_script().resource_path, "res://scenes/ui/game_menu/talisman_page.gd")
	_eq("talisman: tab label 'Tools' at index 1", gm.tab_labels[1].text, "Tools")

func _test_save_roundtrip() -> void:
	gs.reset_to_new_game()
	gs.inventory_item_amount[ITEM_COOL_KEY] = 2
	gs.inventory_item_amount[ITEM_SANDAL] = 1
	gs.inventory_item_amount[ITEM_NEEDLE] = 0
	gs.found_talismans.assign([0, 2])
	gs.equipped_talisman = 2
	gs.red_tools_current_charge.assign([7.0, 0.0, 1.0])
	gs.found_red_tools.assign([0, 2])
	gs.equipped_red_tools.assign([2, 0])
	gs.selected_red_tool_id = 1
	gs.found_blue_tools.assign([1])
	gs.equipped_blue_tools.assign([1])
	gs.found_yellow_tools.assign([0])
	gs.equipped_yellow_tools.assign([0])
	gs.world.enemy_kill_count = {0: 4, 3: 2}
	gs.add_visited_room("DirtCave0")
	gs.add_visited_room("DirtCave2")
	gs.save()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://player.json"))
	var has_all := true
	for k in NEW_FIELDS:
		has_all = has_all and saved.has(k)
	_check("save: player.json contains every new field", has_all)
	gs.reset_to_new_game()
	_eq("save: memory wiped to new-game values", gs.found_talismans, [0])
	_check("save: load_save succeeds", gs.load_save())
	_eq("save round trip: item amounts", gs.inventory_item_amount, [1, 1, 1, 0, 2, 1, 1, 1])
	_eq("save round trip: found talismans", gs.found_talismans, [0, 2])
	_eq("save round trip: equipped talisman", gs.equipped_talisman, 2)
	_eq("save round trip: red tool charges", gs.red_tools_current_charge, [7.0, 0.0, 1.0])
	_eq("save round trip: found / equipped red tools", [gs.found_red_tools, gs.equipped_red_tools], [[0, 2], [2, 0]])
	_eq("save round trip: selected red tool", gs.selected_red_tool_id, 1)
	_eq("save round trip: blue / yellow tools", [gs.found_blue_tools, gs.equipped_blue_tools, gs.found_yellow_tools, gs.equipped_yellow_tools], [[1], [1], [0], [0]])
	_eq("save round trip: kill counts + visited rooms kept", [gs.world.enemy_kill_count, gs.world.visited_rooms], [{0: 4, 3: 2}, ["DirtCave0", "DirtCave2"]])
	_eq("save round trip: typed arrays stay typed (int / float)", [typeof(gs.inventory_item_amount[0]), typeof(gs.red_tools_current_charge[0])], [TYPE_INT, TYPE_FLOAT])

func _test_old_save() -> void:
	# Old (pre-M1) save: the new keys are missing -> new-game defaults, the old keys still load.
	gs.reset_to_new_game()
	gs.copper_shard = 42
	gs.max_hp = 7
	gs.save()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://player.json"))
	for k in NEW_FIELDS:
		old.erase(k)
	var f := FileAccess.open("user://player.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(old, "\t"))
	f.close()
	# memory holds non-default inventory data that must NOT survive the load
	gs.inventory_item_amount.assign([9, 9, 9, 9, 9, 9, 9, 9])
	gs.found_talismans.assign([0, 1, 2])
	gs.equipped_talisman = 1
	gs.red_tools_current_charge.assign([0.0, 0.0, 0.0])
	gs.found_red_tools.assign([0, 1, 2])
	gs.equipped_red_tools.assign([1])
	gs.selected_red_tool_id = 2
	gs.found_blue_tools.assign([0])
	gs.found_yellow_tools.assign([0])
	_check("old save: loads", gs.load_save())
	_eq("old save: old keys load (copper 42, max_hp 7)", [gs.copper_shard, gs.max_hp], [42, 7])
	_eq("old save: item amounts -> new-game defaults", gs.inventory_item_amount, [1, 1, 1, 1, 0, 1, 1, 0])
	_eq("old save: talismans -> [wanderer], wanderer equipped", [gs.found_talismans, gs.equipped_talisman], [[0], 0])
	_eq("old save: red tool charges -> max", gs.red_tools_current_charge, [10.0, 5.0, 2.0])
	_eq("old save: tools -> none found / equipped", [gs.found_red_tools, gs.equipped_red_tools, gs.selected_red_tool_id, gs.found_blue_tools, gs.found_yellow_tools], [[], [], 0, [], []])
	# old world.json without kill counts keeps working
	var w := FileAccess.open("user://world.json", FileAccess.WRITE)
	w.store_string(JSON.stringify({"visited_rooms": ["DirtCave0"]}, "\t"))
	w.close()
	gs.world.enemy_kill_count = {1: 3}
	_check("old save: world.json with only visited_rooms loads", gs.load_save() and gs.world.visited_rooms == ["DirtCave0"])
	# partial new keys: unsaved ones default
	var partial: Dictionary = {"inventory_item_amount": [0, 0, 1], "found_talismans": [0, 1]}
	var p := FileAccess.open("user://player.json", FileAccess.WRITE)
	p.store_string(JSON.stringify(partial))
	p.close()
	gs.load_save()
	_eq("partial save: given keys used (short item array padded with 0)", [gs.inventory_item_amount, gs.found_talismans], [[0, 0, 1, 0, 0, 0, 0, 0], [0, 1]])
	_eq("partial save: missing keys default", [gs.equipped_talisman, gs.red_tools_current_charge], [0, [10.0, 5.0, 2.0]])
	# corrupt values do not crash
	var c := FileAccess.open("user://player.json", FileAccess.WRITE)
	c.store_string(JSON.stringify({"inventory_item_amount": "oops", "found_talismans": 5}))
	c.close()
	_check("corrupt new keys (wrong types) load without crashing, fall back to empty", gs.load_save() and gs.found_talismans == [] and gs.inventory_item_amount == [0, 0, 0, 0, 0, 0, 0, 0])
	gs.delete_save()
	gs.reset_to_new_game()

func _test_debug_inventory() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	_eq("debug inventory: all talismans / tools found", [gs.found_talismans, gs.found_red_tools, gs.found_blue_tools, gs.found_yellow_tools], [[0, 1], [0, 1, 2], [0, 1], [0]])
	gs.grant_debug_inventory()
	_eq("debug inventory: idempotent", gs.found_talismans, [0, 1])
	_eq("debug inventory: does not equip anything", [gs.equipped_red_tools, gs.equipped_blue_tools], [[], []])
	gs.reset_to_new_game()

func _test_cleanup() -> void:
	await _ensure_closed()
	_check("cleanup: freeing the world while the menu is open releases in_menu", await (func() -> bool:
		gm.open(TAB_JOURNAL)
		var p = player
		world.free()
		await process_frame
		return not is_instance_valid(p) or not p.in_menu).call())
	world = null
	await _frames(2)


func _print_table() -> void:
	print("")
	print("%-72s | %-30s | %-30s | %s" % ["Check", "Measured", "Expected", "Result"])
	print("-".repeat(150))
	for r in rows:
		print("%-72s | %-30s | %-30s | %s %s" % [str(r[0]).left(72), str(r[1]).left(30), str(r[2]).left(30), r[3], r[4]])
	print("")
	print("%s  (%d checks, %d failed)" % ["ALL PASS" if fails == 0 else "FAILURES", rows.size(), fails])
