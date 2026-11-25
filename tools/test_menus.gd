extends SceneTree
## Automated menu test: main menu (no save / save / New Game), pause menu (tree pause, control lock,
## Resume, Escape / ui_cancel, hit-stop, blocked during boot / transition / death) and the way back to
## the main menu. Real scenes, input injected as InputEventActions.
## Run: godot --headless --path . -s tools/test_menus.gd
## Any existing user save is backed up and restored; the test works on its own temporary saves.

const MENU_PATH := "res://scenes/ui/main_menu.tscn"
const WORLD_PATH := "res://scenes/world/world.tscn"
const SAVE_FILES: Array[String] = ["user://player.json", "user://world.json"]
const MAX_WAIT_FRAMES := 600
## RoomLoader.StartMode (autoload identifiers are not available to -s scripts).
const NEW_GAME := 0
const CONTINUE := 1

var gs
var rl
var rows: Array = []
var fails: int = 0
var _backup: Dictionary = {}


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rl = root.get_node("RoomLoader")
	_backup_saves()
	gs.delete_save()

	await _test_menu_no_save()
	await _test_menu_with_save_continue()
	await _test_new_game_resets()
	await _test_pause_basics()
	await _test_pause_hitstop()
	await _test_pause_blocked()
	await _test_pause_freezes_game()
	await _test_back_to_menu()
	await _test_world_start_modes()
	await _test_free_while_paused()

	_clear_scene()
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

func _clear_scene() -> void:
	paused = false
	Engine.time_scale = 1.0
	for c in root.get_children():
		if _is_menu(c) or _is_world(c):
			c.free()
	current_scene = null

func _write_save(room: String, chair: String, hp_max: int, copper: int) -> void:
	gs.reset_to_new_game()
	gs.max_hp = hp_max
	gs.current_hp = 1
	gs.current_silk = 5
	gs.copper_shard = copper
	gs.respawn_scene = room
	gs.respawn_chair_name = chair
	gs.add_visited_room("DirtCave0")
	gs.add_visited_room(room)
	gs.save()

func _open_menu() -> Node:
	var menu: Node = (load(MENU_PATH) as PackedScene).instantiate() 
	root.add_child(menu)
	current_scene = menu
	await _frames(3)
	return menu

func _focus_of(menu: Node) -> String:
	var f := menu.get_viewport().gui_get_focus_owner()
	return f.name if f != null else "<none>"

func _wait_world() -> Node:
	await _until(func(): return _is_world(current_scene))
	var w: Node = current_scene 
	await _until(func(): return not rl.is_transitioning())
	await _frames(5)
	return w

func _pause_menu(w: Node) -> Node:
	return w.get_node("PauseMenu")

func _has_world() -> bool:
	for c in root.get_children():
		if _is_world(c):
			return true
	return false


func _is_world(n: Node) -> bool:
	return n != null and n.get_script() != null and n.get_script().resource_path == "res://scenes/world/world.gd"

func _is_menu(n: Node) -> bool:
	return n != null and n.get_script() != null and n.get_script().resource_path == "res://scenes/ui/main_menu.gd"


# --- tests ---

func _test_menu_no_save() -> void:
	gs.delete_save()
	var menu: Node = await _open_menu()
	_eq("menu/no save: initial focus", _focus_of(menu), "NewGame")
	_check("menu/no save: Continue inert", menu.continue_button.inert)
	_check("menu/no save: New Game / Quit active", not menu.new_game_button.inert and not menu.quit_button.inert)
	_check("menu/no save: Continue text alpha 0.2", is_equal_approx(menu.continue_button.get_theme_color("font_color").a, 0.2))
	_eq("menu/no save: New Game text alpha", menu.new_game_button.get_theme_color("font_color").a, 1.0)
	_eq("menu/version label", menu.version_label.text, "v0.1.1")
	_check("menu: select frame on the focused button only", menu.new_game_button.is_frame_visible() and not menu.continue_button.is_frame_visible() and not menu.quit_button.is_frame_visible())
	_check("menu: initial focus is silent", not menu.new_game_button.get_node("SelectSound").playing)
	await _press(&"ui_down")
	_eq("menu: ui_down -> Continue (focusable like Unity)", _focus_of(menu), "Continue")
	_check("menu: frame follows focus", menu.continue_button.is_frame_visible() and not menu.new_game_button.is_frame_visible())
	_check("menu: select sound on focus", menu.continue_button.get_node("SelectSound").playing)
	await _press(&"ui_accept")
	await _frames(10)
	_check("menu/no save: Continue does nothing", current_scene == menu and is_instance_valid(menu) and not _has_world())
	await _press(&"ui_down")
	_eq("menu: ui_down -> Quit", _focus_of(menu), "Quit")
	await _press(&"ui_up")
	await _press(&"ui_up")
	_eq("menu: ui_up back to New Game", _focus_of(menu), "NewGame")
	_clear_scene()
	await process_frame

func _test_menu_with_save_continue() -> void:
	_write_save("DirtCave3", "RestChair", 7, 11)
	gs.reset_to_new_game() # in-memory state differs from the save
	var menu: Node = await _open_menu()
	_eq("menu/save: Continue focused", _focus_of(menu), "Continue")
	_check("menu/save: Continue active", not menu.continue_button.inert)
	_eq("menu/save: Continue text alpha", menu.continue_button.get_theme_color("font_color").a, 1.0)
	await _press(&"ui_accept")
	var w: Node = await _wait_world()
	_check("menu/continue: world is current scene", w != null and current_scene == w)
	await process_frame
	_check("menu/continue: menu freed", not is_instance_valid(menu))
	_eq("menu/continue: room", rl.current_room_name, "DirtCave3")
	_eq("menu/continue: max_hp from save", gs.max_hp, 7)
	_eq("menu/continue: copper from save", gs.copper_shard, 11)
	_eq("menu/continue: silk from save", gs.current_silk, 5)
	_eq("menu/continue: hp refilled by the chair", gs.current_hp, 7)
	_check("menu/continue: player sits on the chair", w.player.resting)
	_eq("menu/continue: control lock 0", w.player.control_lock, 0)
	_clear_scene()
	await process_frame

func _test_new_game_resets() -> void:
	_write_save("DirtCave3", "RestChair", 7, 11)
	var saved_player: String = FileAccess.get_file_as_string("user://player.json")
	var saved_world: String = FileAccess.get_file_as_string("user://world.json")
	gs.copper_shard = 99
	gs.max_hp = 9
	var menu: Node = await _open_menu()
	await _press(&"ui_up") # Continue -> New Game
	_eq("menu/new game: focus moved to New Game", _focus_of(menu), "NewGame")
	await _press(&"ui_accept")
	var w: Node = await _wait_world()
	_eq("menu/new game: room", rl.current_room_name, "DirtCave0")
	_eq("menu/new game: max_hp default", gs.max_hp, 5)
	_eq("menu/new game: hp default", gs.current_hp, 5)
	_eq("menu/new game: copper reset", gs.copper_shard, 0)
	_eq("menu/new game: silk reset", gs.current_silk, 0)
	_eq("menu/new game: respawn scene", gs.respawn_scene, "DirtCave0")
	_eq("menu/new game: respawn chair cleared", gs.respawn_chair_name, "")
	_eq("menu/new game: visited rooms restarted", gs.world.visited_rooms.size(), 1)
	_check("menu/new game: player not on a chair", not w.player.resting)
	_check("menu/new game: save files untouched on disk", FileAccess.get_file_as_string("user://player.json") == saved_player and FileAccess.get_file_as_string("user://world.json") == saved_world)
	# the world stays up for the pause tests

func _test_pause_basics() -> void:
	var w: Node = current_scene 
	var pm: Node = _pause_menu(w)
	await _until(func(): return w.player.is_on_floor(), 300)
	var lock0: int = w.player.control_lock
	_check("pause: closed initially", not pm.is_open() and not paused and not pm.visible)
	await _press(&"pause")
	_check("pause: tree paused", paused)
	_check("pause: menu visible", pm.is_open() and pm.visible)
	_eq("pause: control lock +1", w.player.control_lock, lock0 + 1)
	_eq("pause: time_scale untouched", Engine.time_scale, 1.0)
	_eq("pause: Resume has the focus", _focus_of(pm), "Resume")
	_eq("pause: title text", (pm.get_node("Holder/Title") as Label).text, "PAUSED")
	var pos: Vector2 = w.player.global_position
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await physics_frame
	_check("pause: player frozen", w.player.global_position == pos)
	await _press(&"ui_down")
	_eq("pause: ui_down -> Main Menu", _focus_of(pm), "MainMenu")
	await _press(&"ui_down")
	_eq("pause: ui_down -> Quit", _focus_of(pm), "Quit")
	await _press(&"ui_up")
	await _press(&"ui_up")
	_eq("pause: ui_up back to Resume", _focus_of(pm), "Resume")
	_check("pause: frame on focused button", pm.resume_button.is_frame_visible() and not pm.quit_button.is_frame_visible())
	await _press(&"pause")
	_check("pause: pause key again closes", not paused and not pm.is_open() and not pm.visible)
	_eq("pause: close restores control lock", w.player.control_lock, lock0)
	# Resume button
	await _press(&"pause")
	_check("resume: reopened", paused)
	await _press(&"ui_accept")
	_check("resume: button unpauses", not paused and not pm.is_open())
	_eq("resume: control lock restored", w.player.control_lock, lock0)
	# Escape-style cancel
	await _press(&"pause")
	await _press(&"ui_cancel")
	_check("pause: ui_cancel closes", not paused and not pm.is_open())
	_eq("pause: lock after ui_cancel", w.player.control_lock, lock0)
	# a lock added by someone else while paused survives the round trip
	await _press(&"pause")
	w.player.control_lock += 1
	await _press(&"pause")
	_eq("pause: other lock changes preserved", w.player.control_lock, lock0 + 1)
	w.player.control_lock = lock0

func _test_pause_hitstop() -> void:
	var w: Node = current_scene 
	var pm: Node = _pause_menu(w)
	var lock0: int = w.player.control_lock
	root.get_node("Hitstop").call("freeze", 0.4)
	await _frames(2)
	_eq("hitstop: time_scale 0", Engine.time_scale, 0.0)
	await _press(&"pause")
	_check("hitstop: pause allowed", paused and pm.is_open())
	_eq("hitstop: pause did not touch time_scale", Engine.time_scale, 0.0)
	_check("hitstop: Hitstop restores time_scale while paused", await _until(func(): return Engine.time_scale == 1.0, 240))
	_check("hitstop: still paused", paused)
	await _press(&"pause")
	_check("hitstop: unpaused afterwards", not paused and Engine.time_scale == 1.0)
	_eq("hitstop: lock restored", w.player.control_lock, lock0)

func _test_pause_blocked() -> void:
	var w: Node = current_scene 
	var pm: Node = _pause_menu(w)
	var lock0: int = w.player.control_lock
	# room transition
	rl.load_level("DirtCave0", "")
	await _frames(3)
	_check("blocked: transition running", rl.is_transitioning())
	await _press(&"pause")
	_check("blocked: pause refused during a room transition", not paused and not pm.is_open())
	_check("blocked: transition lock untouched", w.player.control_lock == lock0 + 1)
	await _until(func(): return not rl.is_transitioning())
	await _frames(5)
	_eq("blocked: lock back after transition", w.player.control_lock, lock0)
	await _press(&"pause")
	_check("blocked: pause works again after the transition", paused)
	await _press(&"pause")
	# dead
	w.player.is_dead = true
	await _press(&"pause")
	_check("blocked: pause refused while dead", not paused and not pm.is_open())
	w.player.is_dead = false
	# real death + respawn: pressing pause during the whole sequence never pauses
	var seen_paused := false
	w.player.damaged(99, Vector2.LEFT)
	for i in 8:
		await _press(&"pause")
		seen_paused = seen_paused or paused
		if paused:
			await _press(&"pause")
		await _frames(5)
	_check("blocked: never paused during death / respawn", not seen_paused)
	await _until(func(): return not w.player.is_dead and not rl.is_transitioning(), 900)
	await _frames(5)
	_eq("blocked: lock 0 after respawn", w.player.control_lock, 0)
	await _press(&"pause")
	_check("blocked: pause works after respawn", paused)
	await _press(&"pause")
	_check("blocked: closed again", not paused)

func _test_pause_freezes_game() -> void:
	var w: Node = current_scene 
	var lock0: int = w.player.control_lock
	# the stun timer must not run out while paused
	w.player.damaged(1, Vector2.LEFT)
	await _frames(2)
	_check("freeze: player stunned", w.player.is_hurt)
	await _press(&"pause")
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(gs.stun_time * 1000.0) + 300:
		await process_frame
	_check("freeze: stun does not expire while paused", w.player.is_hurt)
	await _press(&"pause")
	await _until(func(): return not w.player.is_hurt, 300)
	_check("freeze: stun expires after resume", not w.player.is_hurt)
	_eq("freeze: lock back to normal", w.player.control_lock, lock0)

func _test_back_to_menu() -> void:
	var w: Node = current_scene 
	var pm: Node = _pause_menu(w)
	var player: Node = w.player
	var world_ref: WeakRef = weakref(w)
	await _press(&"pause")
	await _press(&"ui_down")
	_eq("menu return: Main Menu focused", _focus_of(pm), "MainMenu")
	await _press(&"ui_accept")
	await _frames(5)
	_check("menu return: world freed", world_ref.get_ref() == null)
	_check("menu return: player freed with it", not is_instance_valid(player))
	_check("menu return: current scene is the main menu", _is_menu(current_scene))
	_check("menu return: tree unpaused", not paused)
	_eq("menu return: time_scale", Engine.time_scale, 1.0)
	_check("menu return: RoomLoader released the world", rl.world == null and rl.player == null and rl.camera == null and rl.room_container == null and rl.current_room == null)
	_check("menu return: no transition left", not rl.is_transitioning())
	_check("menu return: no stray World / Player nodes", not _has_world() and root.find_child("Player", true, false) == null)
	var menu := current_scene 
	_eq("menu return: Continue focused (save on disk)", _focus_of(menu), "Continue")
	# Continue still works after the round trip
	await _press(&"ui_accept")
	var w2: Node = await _wait_world()
	_check("menu return: second world boots", w2 != null and w2 != w)
	_eq("menu return: continue loads the save room", rl.current_room_name, "DirtCave3")
	_eq("menu return: lock 0 in the new world", w2.player.control_lock, 0)
	await _press(&"pause")
	_check("menu return: pause works in the new world", paused)
	await _press(&"pause")
	_check("menu return: and closes", not paused)
	# the very first frames of a new world: boot still running
	_clear_scene()
	await process_frame
	await _open_menu()
	var menu2: Node = current_scene
	menu2.call("_on_new_game")
	_check("boot: world is booting", _is_world(current_scene) and rl.is_transitioning())
	_act(&"pause", true) # same frame as the scene change: the boot is still running
	_act(&"pause", false)
	_check("boot: pause refused while the world boots", not paused)
	await _wait_world()

func _test_world_start_modes() -> void:
	_clear_scene()
	await process_frame
	_write_save("DirtCave3", "RestChair", 7, 11)
	var w: Node = await _direct_world(NEW_GAME)
	_eq("start NEW_GAME with a save: room", rl.current_room_name, "DirtCave0")
	_eq("start NEW_GAME with a save: defaults", [gs.max_hp, gs.copper_shard], [5, 0])
	_check("start NEW_GAME: save kept on disk", gs.save_exists())
	_clear_scene()
	await process_frame
	w = await _direct_world(CONTINUE)
	_eq("start CONTINUE with a save: room", rl.current_room_name, "DirtCave3")
	_eq("start CONTINUE with a save: stats", [gs.max_hp, gs.copper_shard], [7, 11])
	_clear_scene()
	await process_frame
	gs.delete_save()
	gs.reset_to_new_game()
	w = await _direct_world(CONTINUE)
	_eq("start CONTINUE without a save: falls back to a new game", rl.current_room_name, "DirtCave0")
	_clear_scene()
	await process_frame

func _direct_world(mode: int) -> Node:
	var w: Node = (load(WORLD_PATH) as PackedScene).instantiate() 
	w.spawn_debug_dummies = false
	w.set("start_mode", mode)
	root.add_child(w)
	current_scene = w
	await _until(func(): return not rl.is_transitioning())
	await _frames(5)
	return w

func _test_free_while_paused() -> void:
	var w: Node = await _direct_world(NEW_GAME)
	await _press(&"pause")
	_check("free while paused: paused", paused)
	w.free()
	current_scene = null
	await process_frame
	_check("free while paused: tree unpaused when the world leaves", not paused)
	_check("free while paused: RoomLoader released", rl.world == null and not rl.is_transitioning())
	# freeing the world in the middle of a transition must not error or wedge the loader
	var w2: Node = await _direct_world(NEW_GAME)
	rl.load_level("DirtCave0", "")
	await _frames(5)
	w2.free()
	current_scene = null
	await _frames(90) # the stale timer fires and must bail out quietly
	_check("free mid-transition: loader idle", rl.world == null and not rl.is_transitioning())
	var w3: Node = await _direct_world(NEW_GAME)
	_check("free mid-transition: next world boots normally", rl.current_room_name == "DirtCave0" and w3.player.control_lock == 0)


func _print_table() -> void:
	print("")
	print("%-62s | %-26s | %-26s | %s" % ["Check", "Measured", "Expected", "Result"])
	print("-".repeat(130))
	for r in rows:
		print("%-62s | %-26s | %-26s | %s %s" % [r[0], str(r[1]).left(26), str(r[2]).left(26), r[3], r[4]])
	print("")
	print("%s  (%d checks, %d failed)" % ["ALL PASS" if fails == 0 else "FAILURES", rows.size(), fails])
