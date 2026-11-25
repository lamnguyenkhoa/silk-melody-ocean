extends SceneTree
## Automated world test (plan P6): RoomLoader transitions, exits, rest chair, death -> respawn,
## save/load on boot, enemy respawn on room reload. Uses the real world.tscn.
## Run: godot --headless --path . -s tools/test_world.gd
## Any existing user save is backed up and restored; the test works on its own temporary save.
## Physics runs at 60 Hz; _frames() counts only un-frozen frames (hit-stop keeps physics ticking).

const WORLD_PATH := "res://scenes/world/world.tscn"
const SAVE_FILES: Array[String] = ["user://player.json", "user://world.json"]
const FPS := 60.0
## Unity: LevelLoader.transitionTime.
const UNITY_TRANSITION_TIME := 1.0
const TILE := 16
## RoomLoader.StartMode (autoload identifiers are not available to -s scripts).
const NEW_GAME := 0
const CONTINUE := 1

var gs
var rl
var world
var player
var rows: Array = []
var fails: int = 0
var _backup: Dictionary = {}


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rl = root.get_node("RoomLoader")
	_backup_saves()
	_delete_saves()

	await _test_boot_new_game()
	await _test_exit_transitions()
	await _test_disabled_exits()
	await _test_rest_chair()
	await _test_death_respawn_chair()
	await _test_death_respawn_default()
	await _test_boot_with_save()
	await _test_enemy_respawn()

	_restore_saves()
	_print_table()
	quit(1 if fails > 0 else 0)


# --- helpers ---

func _backup_saves() -> void:
	for p in SAVE_FILES:
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)

func _delete_saves() -> void:
	gs.delete_save()

func _restore_saves() -> void:
	_delete_saves()
	for p in _backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(_backup[p])
		f.close()

func _frames(n: int) -> void:
	var counted := 0
	while counted < n:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1

func _settle() -> void:
	var guard := 0
	while not is_equal_approx(Engine.time_scale, 1.0) and guard < 900:
		await physics_frame
		guard += 1

func _act(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _release_all() -> void:
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"dash", &"attack", &"parry"]:
		if Input.is_action_pressed(a):
			_act(a, false)

func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1

## Fresh world (no debug dummies). Boots through RoomLoader.start(mode) exactly like the main scene (the menu's New Game / Continue).
func _boot_world(mode: int = NEW_GAME) -> void:
	if world != null and is_instance_valid(world):
		world.free()
		await process_frame
	world = (load(WORLD_PATH) as PackedScene).instantiate()
	world.spawn_debug_dummies = false
	world.set("start_mode", mode)
	root.add_child(world)
	player = world.get_node("Player")
	await _frames(3)

func _room_marker(room: Node, marker_name: String) -> Node2D:
	return room.get_node_or_null(marker_name) as Node2D

func _limits() -> Rect2i:
	var cam = world.get_node("GameCamera")
	return Rect2i(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)

func _expected_limits(room: Node) -> Rect2i:
	var r: Rect2i = (room.get_node("Tilemap") as TileMapLayer).get_used_rect()
	return Rect2i(r.position * TILE, r.size * TILE)

## Finds the room's exit leading to [param level] (optionally with a given spawn name).
func _find_exit(room: Node, level: String, spawn: String = ""):
	for c in room.get_children():
		if c.get("level_name") != null and c.level_name == level and (spawn == "" or c.spawn_pos_name == spawn):
			return c
	return null

func _teleport(pos: Vector2) -> void:
	player.global_position = pos
	player.velocity = Vector2.ZERO

## Teleports onto an exit trigger and measures the transition. Returns a dictionary with
## frames_to_swap, frames_fade_in, pos_at_swap, lock_at_swap, alpha_mid.
func _take_exit(exit_node, target_room: String) -> Dictionary:
	var res := {"swap_frames": -1, "fade_in_frames": -1, "pos": Vector2.ZERO, "lock": -1, "alpha_mid": -1.0, "hp": gs.current_hp}
	var holder := {"pos": Vector2.ZERO, "lock": -1, "swapped": false}
	var cb := func(_room: Node, _nm: String) -> void:
		holder["pos"] = player.global_position
		holder["lock"] = player.control_lock
		holder["swapped"] = true
	rl.room_loaded.connect(cb)
	var fader = world.get_node("Fader")
	_teleport(exit_node.global_position + exit_node.box_offset)
	var frames := 0
	var started := -1
	while frames < 300 and not holder["swapped"]:
		await physics_frame
		if Engine.time_scale <= 0.0:
			continue
		frames += 1
		if started < 0 and player.control_lock > 0:
			started = frames
		if started >= 0 and frames - started == 30:
			res["alpha_mid"] = fader.alpha()
	rl.room_loaded.disconnect(cb)
	if holder["swapped"]:
		res["swap_frames"] = frames - started
		res["pos"] = holder["pos"]
		res["lock"] = holder["lock"]
	var fi := 0
	while fi < 200 and fader.alpha() > 0.0:
		await physics_frame
		if Engine.time_scale > 0.0:
			fi += 1
	res["fade_in_frames"] = fi
	return res


# --- tests ---

func _test_boot_new_game() -> void:
	await _boot_world()
	var room = rl.current_room
	var start := _room_marker(room, "PlayerStart")
	var near_start: bool = player.global_position.distance_to(start.global_position) < 40.0
	_add("boot, no save: new game in DirtCave0", "room=%s, player (%.1f,%.1f) vs PlayerStart (%.1f,%.1f), hp %d/%d, silk %d" % [rl.current_room_name, player.global_position.x, player.global_position.y, start.global_position.x, start.global_position.y, gs.current_hp, gs.max_hp, gs.current_silk],
			"DirtCave0, at PlayerStart (falling), default stats", rl.current_room_name == "DirtCave0" and near_start and gs.current_hp == 5 and gs.current_silk == 0 and gs.respawn_scene == "DirtCave0")
	_add("boot: respawn_pos = PlayerStart, no chair", "respawn_pos=%s chair='%s' visited=%s" % [gs.respawn_pos, gs.respawn_chair_name, gs.world.visited_rooms],
			"PlayerStart, '', [DirtCave0]", gs.respawn_pos.is_equal_approx(start.global_position) and gs.respawn_chair_name == "" and gs.world.visited_rooms == ["DirtCave0"])
	_add("boot: camera limits from the room", "%s" % [_limits()], "%s" % [_expected_limits(room)], _limits() == _expected_limits(room))
	_add("boot: player in group 'player', controllable, no save file written", "lock=%d kinematic=%s save_exists=%s container children=%d" % [player.control_lock, player.is_kinematic, gs.save_exists(), world.get_node("RoomContainer").get_child_count()],
			"lock 0, dynamic, no save, 1 room", player.is_in_group("player") and player.control_lock == 0 and not player.is_kinematic and not gs.save_exists() and world.get_node("RoomContainer").get_child_count() == 1)
	_add("room scene name mapping", "%s %s" % [rl.room_path("DirtCave0"), rl.room_path("DirtCave14")], "dirt_cave_0 / dirt_cave_14",
			rl.room_path("DirtCave0") == "res://scenes/rooms/dirt_cave_0.tscn" and rl.room_path("DirtCave14") == "res://scenes/rooms/dirt_cave_14.tscn")
	# Let the player land.
	await _frames(120)


func _check_arrival(label: String, res: Dictionary, room_name: String, spawn: String) -> void:
	var room = rl.current_room
	var marker := _room_marker(room, spawn)
	var dist: float = (res["pos"] as Vector2).distance_to(marker.global_position)
	_add("%s: swap after the fade-out" % label, "swap %d frames after the lock (%.3f s), mid-fade alpha %.2f, fade-in cleared after %d frames" % [res["swap_frames"], res["swap_frames"] / FPS, res["alpha_mid"], res["fade_in_frames"]],
			"%.2f s (Unity transitionTime), alpha 0.5, fade-in 1 s" % UNITY_TRANSITION_TIME,
			absi(int(res["swap_frames"]) - 60) <= 3 and absf(float(res["alpha_mid"]) - 0.5) < 0.1 and absi(int(res["fade_in_frames"]) - 60) <= 4)
	_add("%s: lands at %s/%s" % [label, room_name, spawn], "room=%s, player at swap %s vs marker %s (d=%.2f), lock at swap %d, camera limits %s" % [rl.current_room_name, res["pos"], marker.global_position, dist, res["lock"], _limits()],
			"room %s, on the marker, lock 0, limits %s" % [room_name, _expected_limits(room)],
			rl.current_room_name == room_name and dist < 0.01 and int(res["lock"]) == 0 and _limits() == _expected_limits(room)
			and world.get_node("RoomContainer").get_child_count() == 1)

func _test_exit_transitions() -> void:
	# DirtCave0 -> DirtCave1
	var hp0: int = gs.current_hp
	var res := await _take_exit(_find_exit(rl.current_room, "DirtCave1"), "DirtCave1")
	_check_arrival("exit 0->1", res, "DirtCave1", "Entry0")
	_add("visited_rooms after 0->1", "%s" % [gs.world.visited_rooms], "[DirtCave0, DirtCave1]", gs.world.visited_rooms == ["DirtCave0", "DirtCave1"])
	var arrival_pos: Vector2 = player.global_position
	await _frames(90)
	_add("stays in DirtCave1 after arriving (no re-trigger)", "room=%s, lock %d, moved %.1f px" % [rl.current_room_name, player.control_lock, player.global_position.distance_to(arrival_pos)], "DirtCave1, lock 0", rl.current_room_name == "DirtCave1" and player.control_lock == 0)
	# DirtCave1 -> DirtCave0 (back, Entry0)
	res = await _take_exit(_find_exit(rl.current_room, "DirtCave0"), "DirtCave0")
	_check_arrival("exit 1->0 (back)", res, "DirtCave0", "Entry0")
	await _frames(90)
	_add("stays in DirtCave0 after returning", "room=%s, lock %d" % [rl.current_room_name, player.control_lock], "DirtCave0, lock 0", rl.current_room_name == "DirtCave0" and player.control_lock == 0)
	# 0 -> 1 -> 2 -> 3 and back 3 -> 2 (Entry1)
	res = await _take_exit(_find_exit(rl.current_room, "DirtCave1"), "DirtCave1")
	await _frames(30)
	res = await _take_exit(_find_exit(rl.current_room, "DirtCave2", "Entry0"), "DirtCave2")
	_check_arrival("exit 1->2", res, "DirtCave2", "Entry0")
	await _frames(30)
	res = await _take_exit(_find_exit(rl.current_room, "DirtCave3"), "DirtCave3")
	_check_arrival("exit 2->3", res, "DirtCave3", "Entry0")
	await _frames(60)
	res = await _take_exit(_find_exit(rl.current_room, "DirtCave2"), "DirtCave2")
	_check_arrival("exit 3->2 (Entry1)", res, "DirtCave2", "Entry1")
	_add("visited_rooms after the walk 0->1->2->3->2", "%s" % [gs.world.visited_rooms], "[DirtCave0..3]", gs.world.visited_rooms == ["DirtCave0", "DirtCave1", "DirtCave2", "DirtCave3"])
	_add("player node never freed", "same node valid=%s, in group player=%s" % [is_instance_valid(player), player.is_in_group("player")], "valid", is_instance_valid(player) and player.is_in_group("player"))
	_add("exits do not save", "save_exists=%s" % gs.save_exists(), "false", not gs.save_exists())

func _test_disabled_exits() -> void:
	await _frames(60)
	var room = rl.current_room
	var ok := true
	var txt := ""
	for lvl in ["DirtCave14", "DirtCave4"]:
		var ex = _find_exit(room, lvl)
		if ex == null:
			ok = false
			txt += "%s: exit missing! " % lvl
			continue
		_teleport(ex.global_position + ex.box_offset)
		await _frames(120)
		var stayed: bool = rl.current_room_name == "DirtCave2" and player.control_lock == 0 and world.get_node("Fader").alpha() == 0.0 and is_instance_valid(room) and room == rl.current_room
		txt += "%s: disabled=%s stayed=%s; " % [lvl, ex.disabled, stayed]
		ok = ok and ex.disabled and stayed
	_add("disabled exits (DirtCave2 -> DirtCave14 / DirtCave4) are inert", txt, "both disabled, no transition for 2 s", ok)


func _test_rest_chair() -> void:
	await _release_all_then_go("DirtCave3")
	var room = rl.current_room
	var chair = room.get_node("RestChair")
	var sit: Node2D = chair.get_node("SitSpot")
	# Hurt state: hp 2, silk 5, copper 7 (recovery must restore hp only).
	gs.current_hp = 2
	gs.current_silk = 5
	gs.copper_shard = 7
	gs.stats_changed.emit()
	_teleport(chair.global_position + Vector2(20, 8))
	await _frames(10)
	_add("chair: in range, label shown", "in_range=%s label=%s sitting=%s" % [chair.player_in_range, chair.get_node("InteractLabel").visible, chair.sitting], "in range, label visible, not sitting", chair.player_in_range and chair.get_node("InteractLabel").visible and not chair.sitting)
	_act(&"move_up", true)
	await _frames(4)
	var saved_player: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://player.json")) if FileAccess.file_exists("user://player.json") else {}
	var saved_world: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://world.json")) if FileAccess.file_exists("user://world.json") else {}
	_add("chair: up sits, hp restored, silk/copper kept", "sitting=%s resting=%s kinematic=%s pos=%s sit=%s hp=%d/%d silk=%d copper=%d label=%s" % [chair.sitting, player.resting, player.is_kinematic, player.global_position, sit.global_position, gs.current_hp, gs.max_hp, gs.current_silk, gs.copper_shard, chair.get_node("InteractLabel").visible],
			"sits at SitSpot, hp 5/5, silk 5 (Unity restores hp only), copper 7, label hidden",
			chair.sitting and player.resting and player.is_kinematic and player.global_position.distance_to(sit.global_position) < 0.01 and gs.current_hp == 5 and gs.current_silk == 5 and gs.copper_shard == 7 and not chair.get_node("InteractLabel").visible)
	_add("chair: respawn point set", "chair='%s' scene='%s'" % [gs.respawn_chair_name, gs.respawn_scene], "RestChair / DirtCave3", gs.respawn_chair_name == "RestChair" and gs.respawn_scene == "DirtCave3")
	_add("chair: game saved", "player.json: hp %s silk %s copper %s chair '%s' scene '%s'; world.json visited %s" % [saved_player.get("current_hp"), saved_player.get("current_silk"), saved_player.get("copper_shard"), saved_player.get("respawn_chair_name"), saved_player.get("respawn_scene"), saved_world.get("visited_rooms")],
			"hp 5, silk 5, copper 7, RestChair, DirtCave3, 4 rooms",
			not saved_player.is_empty() and int(saved_player["current_hp"]) == 5 and int(saved_player["current_silk"]) == 5 and int(saved_player["copper_shard"]) == 7 and saved_player["respawn_chair_name"] == "RestChair" and saved_player["respawn_scene"] == "DirtCave3" and (saved_world["visited_rooms"] as Array).size() == 4)
	_add("chair: shows Saving... and soft flash", "saving visible=%s flash alpha=%.3f (start %.3f)" % [chair.get_node("Ui/SavingText").visible, chair.get_node("Ui/SoftFlash").color.a, 100.0 / 255.0], "visible, ~0.39 decaying 0.3/s", chair.get_node("Ui/SavingText").visible and chair.get_node("Ui/SoftFlash").color.a > 0.3)
	# Invulnerable while sitting.
	var hp_before: int = gs.current_hp
	player.damaged(1, Vector2.ZERO)
	await _frames(2)
	_add("chair: invulnerable while sitting (in_i_frame, hurtbox off)", "in_i_frame=%s hurtbox monitoring=%s, hp after damaged(1)=%d" % [player.in_i_frame, player.hurtbox.monitoring, gs.current_hp], "i-frame, off, hp unchanged", player.in_i_frame and not player.hurtbox.monitoring and gs.current_hp == hp_before)
	# Controls locked while resting: movement input does nothing.
	_act(&"move_up", false)
	_act(&"move_right", true)
	_act(&"jump", true)
	await _frames(20)
	var held: bool = player.global_position.distance_to(sit.global_position) < 0.01
	_act(&"move_right", false)
	_act(&"jump", false)
	_add("chair: no control while resting", "still at SitSpot=%s" % held, "true", held and chair.sitting)
	await _frames(70)
	_add("chair: Saving... hidden after 1 s, flash faded", "saving visible=%s flash alpha=%.3f" % [chair.get_node("Ui/SavingText").visible, chair.get_node("Ui/SoftFlash").color.a], "hidden, ~0 after 1.3 s", not chair.get_node("Ui/SavingText").visible and chair.get_node("Ui/SoftFlash").color.a < 0.05)
	# Stand up.
	_act(&"move_down", true)
	await _frames(4)
	_act(&"move_down", false)
	await _frames(20)
	_add("chair: down stands up", "sitting=%s resting=%s kinematic=%s in_i_frame=%s hurtbox=%s label=%s" % [chair.sitting, player.resting, player.is_kinematic, player.in_i_frame, player.hurtbox.monitoring, chair.get_node("InteractLabel").visible],
			"all released, label back", not chair.sitting and not player.resting and not player.is_kinematic and not player.in_i_frame and player.hurtbox.monitoring and chair.get_node("InteractLabel").visible)
	hp_before = gs.current_hp
	player.damaged(1, Vector2.ZERO)
	await _frames(2)
	_add("chair: damage works again after standing", "hp %d -> %d" % [hp_before, gs.current_hp], "-1", gs.current_hp == hp_before - 1)
	await _frames(100)
	_release_all()


func _release_all_then_go(room_name: String) -> void:
	_release_all()
	# Already in DirtCave3 from the exit test? (the walk ended in DirtCave2) -> go there directly.
	if rl.current_room_name != room_name:
		rl.load_level(room_name, "Entry0")
		await _frames(60 + 4)
		await _frames(70)
	await _settle()


func _test_death_respawn_chair() -> void:
	var node_id: int = player.get_instance_id()
	# Player stands in DirtCave3 near the chair after the previous test; move away from the chair, kill.
	var chair = rl.current_room.get_node("RestChair")
	var sit: Node2D = chair.get_node("SitSpot")
	_teleport(chair.global_position + Vector2(-30, 0))
	gs.current_hp = 1
	gs.current_silk = 3
	await _frames(100) # let any i-frames from the previous test pass
	player.in_i_frame = false
	player.damaged(1, Vector2.ZERO)
	await physics_frame
	var hp_now: int = gs.current_hp
	var dead_now: bool = player.is_dead and player.is_kinematic and hp_now == 0
	var lock_now: int = player.control_lock
	# Measure until the player sits again.
	var frames := 0
	var respawned_frame := -1
	var room_changed_at := -1
	var old_room = rl.current_room
	while frames < 300:
		await physics_frame
		if Engine.time_scale <= 0.0:
			continue
		frames += 1
		if room_changed_at < 0 and rl.current_room != old_room:
			room_changed_at = frames
			break
	await _frames(2)
	var new_chair = rl.current_room.get_node("RestChair")
	sit = new_chair.get_node("SitSpot")
	var at_chair: bool = player.global_position.distance_to(sit.global_position) < 0.5
	_add("death: dead state during the fade", "is_dead=%s kinematic=%s hp=%d lock=%d" % [dead_now, player.is_kinematic, hp_now, lock_now], "dead, kinematic, hp 0, lock 2 (Unity: Death +1, LoadLevel +1)", dead_now and lock_now == 2)
	_add("death: respawn swap after the fade-out", "room swapped %d frames after the hit (%.3f s)" % [room_changed_at, room_changed_at / FPS], "%.2f s (Unity transitionTime)" % UNITY_TRANSITION_TIME, absi(room_changed_at - 60) <= 3)
	_add("death: respawned sitting on the chair, same player node", "room=%s at_chair=%s sitting=%s resting=%s kinematic=%s i_frame=%s same_node=%s hp=%d silk=%d" % [rl.current_room_name, at_chair, new_chair.sitting, player.resting, player.is_kinematic, player.in_i_frame, player.get_instance_id() == node_id, gs.current_hp, gs.current_silk],
			"DirtCave3 chair, sitting, hp max, same node, silk kept",
			rl.current_room_name == "DirtCave3" and at_chair and new_chair.sitting and player.resting and player.is_kinematic and player.in_i_frame and player.get_instance_id() == node_id and gs.current_hp == gs.max_hp and gs.current_silk == 3)
	await _frames(70)
	_add("death: flags cleared after the transition", "is_dead=%s lock=%d hp=%d fader alpha=%.2f" % [player.is_dead, player.control_lock, gs.current_hp, world.get_node("Fader").alpha()], "alive, lock 0, hp max, clear", not player.is_dead and player.control_lock == 0 and gs.current_hp == gs.max_hp and world.get_node("Fader").alpha() == 0.0)
	# Stand up so it can walk again.
	_act(&"move_down", true)
	await _frames(4)
	_act(&"move_down", false)
	await _frames(60)
	_add("death: can move after standing from the respawn chair", "resting=%s lock=%d kinematic=%s grounded=%s" % [player.resting, player.control_lock, player.is_kinematic, player.is_grounded], "free", not player.resting and player.control_lock == 0 and not player.is_kinematic)


func _test_death_respawn_default() -> void:
	# No chair yet (new game, died before the first chair): respawn at respawn_pos in respawn_scene.
	var room0_start: Vector2
	var tmp = (load("res://scenes/rooms/dirt_cave_0.tscn") as PackedScene).instantiate()
	room0_start = (tmp.get_node("PlayerStart") as Node2D).position
	tmp.free()
	gs.respawn_chair_name = ""
	gs.respawn_scene = "DirtCave0"
	gs.respawn_pos = room0_start
	gs.current_hp = 2
	gs.stats_changed.emit()
	await _frames(100)
	player.in_i_frame = false
	player.damaged(5, Vector2.ZERO)
	await physics_frame
	var dead_now: bool = player.is_dead
	var frames := 0
	var old_room = rl.current_room
	while frames < 300 and rl.current_room == old_room:
		await physics_frame
		if Engine.time_scale > 0.0:
			frames += 1
	var pos_at_swap: Vector2 = player.global_position
	await _frames(70)
	_add("death without chair: respawn at default position", "dead=%s room=%s swap after %d frames, pos at swap %s vs respawn_pos %s, kinematic=%s hp=%d/%d lock=%d dead_now=%s" % [dead_now, rl.current_room_name, frames, pos_at_swap, room0_start, player.is_kinematic, gs.current_hp, gs.max_hp, player.control_lock, player.is_dead],
			"DirtCave0 at respawn_pos, dynamic, hp max, lock 0",
			dead_now and rl.current_room_name == "DirtCave0" and pos_at_swap.distance_to(room0_start) < 0.01 and not player.is_kinematic and gs.current_hp == gs.max_hp and player.control_lock == 0 and not player.is_dead and absi(frames - 60) <= 3)
	_add("death without chair: still controllable (moves under gravity)", "moved to %s, resting=%s" % [player.global_position, player.resting], "free", not player.resting and not player.is_kinematic)


func _test_boot_with_save() -> void:
	# Save at the chair state, wipe the in-memory state and boot a fresh world: must continue from the save.
	gs.reset_to_new_game()
	gs.respawn_scene = "DirtCave3"
	gs.respawn_chair_name = "RestChair"
	gs.current_hp = 3
	gs.max_hp = 6
	gs.current_silk = 5
	gs.copper_shard = 11
	gs.lifeblood_hp = 1
	gs.add_visited_room("DirtCave0")
	gs.add_visited_room("DirtCave3")
	gs.world.enemy_kill_count[1] = 2
	gs.save()
	gs.reset_to_new_game()
	_add("boot-with-save setup: memory wiped", "hp=%d copper=%d scene=%s" % [gs.current_hp, gs.copper_shard, gs.respawn_scene], "defaults", gs.current_hp == 5 and gs.copper_shard == 0 and gs.respawn_scene == "DirtCave0")
	await _boot_world(CONTINUE)
	var room = rl.current_room
	var chair = room.get_node("RestChair")
	var sit: Node2D = chair.get_node("SitSpot")
	_add("boot with save: room, position, stats", "room=%s pos=%s sit=%s sitting=%s resting=%s hp=%d/%d silk=%d copper=%d lifeblood=%d visited=%s kills=%s" % [rl.current_room_name, player.global_position, sit.global_position, chair.sitting, player.resting, gs.current_hp, gs.max_hp, gs.current_silk, gs.copper_shard, gs.lifeblood_hp, gs.world.visited_rooms, gs.world.enemy_kill_count],
			"DirtCave3 on the chair, hp 6/6 (chair recovery), silk 5, copper 11, lifeblood 1, visited kept, kills {1: 2}",
			rl.current_room_name == "DirtCave3" and player.global_position.distance_to(sit.global_position) < 0.5 and chair.sitting and player.resting
			and gs.max_hp == 6 and gs.current_hp == 6 and gs.current_silk == 5 and gs.copper_shard == 11 and gs.lifeblood_hp == 1
			and gs.world.visited_rooms == ["DirtCave0", "DirtCave3"] and gs.world.enemy_kill_count == {1: 2})
	_add("boot with save: camera limits and control", "limits ok=%s lock=%d" % [_limits() == _expected_limits(room), player.control_lock], "room limits, lock 0", _limits() == _expected_limits(room) and player.control_lock == 0)
	# HUD shows the loaded stats (6 masks + 1 lifeblood = 7, 5 of 8 silk segments, shard label 11).
	await _frames(2)
	var hud = world.get_node("HUD")
	var filled_silk: int = 0
	for seg in hud.silk_segments:
		if seg.texture == hud.silk_filled:
			filled_silk += 1
	_add("boot with save: HUD shows the loaded stats", "masks=%d, silk segments=%d (filled %d), shards '%s'" % [hud.masks.size(), hud.silk_segments.size(), filled_silk, hud.shard_count.text],
			"7 masks, 8 segments (5 filled), '11'", hud.masks.size() == 7 and hud.silk_segments.size() == 8 and filled_silk == 5 and hud.shard_count.text == "11")


func _test_enemy_respawn() -> void:
	# Go to DirtCave1, kill an enemy, leave and come back: all enemies are fresh again.
	gs.reset_to_new_game()
	await _boot_world()
	rl.load_level("DirtCave1", "Entry0")
	await _frames(70)
	var room1 = rl.current_room
	var enemies: Array = []
	for c in room1.get_children():
		if c.is_in_group("enemy_spawns"):
			enemies.append(c)
	var victim = enemies[0]
	var total: int = enemies.size()
	var victim_type: int = victim.enemy_type
	# Keep the player safe from the enemies while this runs.
	player.is_kinematic = true
	player.global_position = Vector2(0, -5000)
	victim.damaged(999, Vector2.ZERO)
	await _frames(5)
	var kills: int = int(gs.world.enemy_kill_count.get(victim_type, 0))
	var victim_dead: bool = victim.is_dead
	var dead_count := 0
	for e in enemies:
		if e.is_dead:
			dead_count += 1
	await _settle()
	player.is_kinematic = false
	rl.load_level("DirtCave2", "Entry0")
	await _frames(70)
	rl.load_level("DirtCave1", "Entry1")
	await _frames(70)
	var room1b = rl.current_room
	var fresh: Array = []
	for c in room1b.get_children():
		if c.is_in_group("enemy_spawns"):
			fresh.append(c)
	var all_alive := true
	var all_full := true
	for e in fresh:
		if e.is_dead:
			all_alive = false
		if e.current_hp != e.max_hp:
			all_full = false
	_add("enemy respawn on room reload", "victim dead=%s dead before=%d/%d, kills(type)=%d; after reload: %d enemies, all alive=%s, full hp=%s, new room instance=%s, old room freed=%s" % [victim_dead, dead_count, total, kills, fresh.size(), all_alive, all_full, room1b != room1, not is_instance_valid(room1) or room1.is_queued_for_deletion()],
			"%d fresh enemies at full hp (kill count stays in GameState)" % total,
			victim_dead and dead_count == 1 and kills == 1 and fresh.size() == total and all_alive and all_full and room1b != room1 and int(gs.world.enemy_kill_count.get(victim_type, 0)) == 1)
	# Reloaded rooms are the only room in the container (old one removed).
	_add("room container holds exactly one room", "children=%d" % world.get_node("RoomContainer").get_child_count(), "1", world.get_node("RoomContainer").get_child_count() == 1)
	if world != null and is_instance_valid(world):
		world.free()


func _print_table() -> void:
	print("")
	print("=== P6 world test (60 Hz physics) ===")
	for r: Array in rows:
		print("[%s] %-56s measured: %s | expected: %s%s" % [r[3], r[0], r[1], r[2], ("  (" + (r[4] as String) + ")") if (r[4] as String) != "" else ""])
	print("test_world: ", "FAILED (%d)" % fails if fails > 0 else "ALL PASS")
