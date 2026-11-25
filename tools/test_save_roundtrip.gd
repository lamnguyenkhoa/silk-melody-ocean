extends SceneTree
## Headless test: godot --headless --path . -s tools/test_save_roundtrip.gd
## Backs up any existing user save and restores it afterwards.

func _initialize() -> void:
	# Autoloads are not in the tree yet during _initialize; wait one frame.
	await process_frame
	var gs: Node = root.get_node("GameState")
	var backup := {}
	for p: String in ["user://player.json", "user://world.json"]:
		if FileAccess.file_exists(p):
			backup[p] = FileAccess.get_file_as_string(p)
	var ok := true
	gs.reset_to_new_game()
	gs.max_hp = 7
	gs.current_hp = 3
	gs.lifeblood_hp = 2
	gs.current_silk = 5
	gs.copper_shard = 42
	gs.respawn_scene = "DirtCave3"
	gs.respawn_chair_name = "RestChair"
	gs.respawn_pos = Vector2(12.5, -34.0)
	gs.add_visited_room("DirtCave0")
	gs.add_visited_room("DirtCave1")
	gs.add_visited_room("DirtCave1")
	gs.world.enemy_kill_count[0] = 3
	gs.world.enemy_kill_count[3] = 1
	gs.save()
	ok = _check(gs.save_exists(), "save_exists after save") and ok
	gs.reset_to_new_game()
	ok = _check(gs.max_hp == 5 and gs.copper_shard == 0 and gs.world.visited_rooms.is_empty(), "reset restores defaults") and ok
	ok = _check(gs.load_save(), "load_save returns true") and ok
	ok = _check(gs.max_hp == 7, "max_hp") and ok
	ok = _check(gs.current_hp == 3, "current_hp") and ok
	ok = _check(gs.lifeblood_hp == 2, "lifeblood_hp") and ok
	ok = _check(gs.current_silk == 5, "current_silk") and ok
	ok = _check(gs.copper_shard == 42, "copper_shard") and ok
	ok = _check(gs.respawn_scene == "DirtCave3", "respawn_scene") and ok
	ok = _check(gs.respawn_chair_name == "RestChair", "respawn_chair_name") and ok
	ok = _check(gs.respawn_pos == Vector2(12.5, -34.0), "respawn_pos") and ok
	ok = _check(gs.world.visited_rooms == ["DirtCave0", "DirtCave1"], "visited_rooms") and ok
	ok = _check(gs.world.enemy_kill_count == {0: 3, 3: 1}, "enemy_kill_count") and ok
	ok = _check(gs.move_speed == 112.0, "untouched default preserved") and ok
	gs.delete_save()
	ok = _check(not gs.save_exists(), "delete_save") and ok
	# Hitstop overlap check: the earlier (shorter) call must not reset the latest one.
	var hs: Node = root.get_node("Hitstop")
	# Let a few ordinary frames pass first: the first frames after boot carry a large delta
	# (startup time), which would fire every pending timer in one tick and make this check flaky.
	for i in 3:
		await process_frame
	hs.slow(0.5, 0.05)
	hs.slow(0.2, 0.15)
	await create_timer(0.1, true, false, true).timeout
	ok = _check(is_equal_approx(Engine.time_scale, 0.2), "hitstop: earlier call must not reset latest") and ok
	await create_timer(0.2, true, false, true).timeout
	ok = _check(is_equal_approx(Engine.time_scale, 1.0), "hitstop: restored to 1.0") and ok
	# Restore any pre-existing user saves.
	for p: String in backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(backup[p])
		f.close()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _check(cond: bool, label: String) -> bool:
	if not cond:
		printerr("FAIL: ", label)
	return cond
