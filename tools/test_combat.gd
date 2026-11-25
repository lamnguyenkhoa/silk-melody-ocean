extends SceneTree
## Automated combat test (plan P3). Flat constructed room with the real tileset, the real player
## scene and the real training dummy. Simulates inputs and measures slash / pogo / parry / damage.
## Run: godot --headless --path . -s tools/test_combat.gd
## Physics runs at 60 Hz here. NOTE: while a hit-stop freeze is active (Engine.time_scale 0) physics
## frames still fire (with delta 0), so _frames()/_wait_until() count only un-frozen frames
## ("game frames"); _thaw() waits for the freeze to end and returns its real duration in ms.

const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const DUMMY_PATH := "res://scenes/enemies/training_dummy.tscn"
const SOLID_ATLAS := Vector2i(3, 3)
const FLOOR_X := [-40, 40]
const FLOOR_Y := [0, 2]
const REST_Y := -14.3            # player origin standing on the floor (floor top at y = 0)
const DUMMY_REST_Y := -14.75     # dummy origin standing on the floor (body bottom = origin + 14.75)
const DUMMY_HP := 999
const FPS := 60.0

var player # untyped: class names / autoloads are not resolvable when this script is compiled
var gs # GameState autoload node
var dummy
var rows: Array = []
var fails: int = 0
var tilemap: TileMapLayer
var died_count: int = 0


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	_build_room()
	player = (load(PLAYER_PATH) as PackedScene).instantiate()
	root.add_child(player)
	player.died.connect(func() -> void: died_count += 1)
	player.global_position = Vector2(0, REST_Y)
	await _frames(20)

	await _test_forward_slash()
	await _test_forward_slash_left()
	await _test_up_slash()
	await _test_attack_cooldown()
	await _test_pogo_enemy()
	await _test_pogo_floor()
	await _test_damage()
	await _test_lifeblood()
	await _test_parry()
	await _test_parry_late()
	await _test_contact()
	await _test_death()

	_print_table()
	quit(1 if fails > 0 else 0)


# --- helpers ---

func _build_room() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "Tilemap"
	tilemap.tile_set = load(TILESET_PATH) as TileSet
	root.add_child(tilemap)
	for x in range(FLOOR_X[0] as int, (FLOOR_X[1] as int) + 1):
		for y in range(FLOOR_Y[0] as int, (FLOOR_Y[1] as int) + 1):
			tilemap.set_cell(Vector2i(x, y), 0, SOLID_ATLAS)


## Waits n un-frozen physics frames (frames during a hit-stop freeze are not counted).
func _frames(n: int) -> void:
	var counted := 0
	while counted < n:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1


## Waits until a running hit-stop freeze is over. Returns the real time waited in ms.
func _thaw() -> int:
	var t0: int = Time.get_ticks_msec()
	var guard := 0
	while Engine.time_scale == 0.0 and guard < 600:
		await physics_frame
		guard += 1
	return Time.get_ticks_msec() - t0


func _act(action: StringName, pressed: bool, strength: float = 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = strength if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_all() -> void:
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"dash", &"attack", &"parry"]:
		if Input.is_action_pressed(a):
			_act(a, false)


func _tap(action: StringName) -> void:
	_act(action, true)
	await physics_frame
	_act(action, false)


func _slash_count() -> int:
	var n := 0
	for c in player.visual.get_children():
		if c is Area2D:
			n += 1
	return n


func _clear_slashes() -> void:
	for c in player.visual.get_children():
		if c is Area2D:
			c.queue_free()


func _remove_dummy() -> void:
	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null


func _spawn_dummy(pos: Vector2, gravity_scale: float = 1.0) -> void:
	_remove_dummy()
	dummy = (load(DUMMY_PATH) as PackedScene).instantiate()
	dummy.position = pos
	dummy.gravity_scale = gravity_scale
	root.add_child(dummy)


## Clears all transient state, puts the player on the floor at x, resets GameState numbers.
func _reset(x: float = 0.0, y: float = REST_Y) -> void:
	_release_all()
	await _frames(3) # let the previous test's last input edge be consumed
	await _thaw()
	_remove_dummy()
	_clear_slashes()
	Engine.time_scale = 1.0
	player.rest_chair_recovery()
	player.anim.stop()
	player.anim_override = &""
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	player.is_dashing = false
	player.is_jumping = false
	player.is_dead = false
	player.is_kinematic = false
	player.control_lock = 0
	player.gravity_on = true
	player.is_facing_left = false
	player.visual.scale.x = 1.0
	player.coyote_air_timer = 0.0
	player.air_time = 0.0
	player.attack_timer = 10.0
	player.parry_timer = 10.0
	player.hurtbox.monitoring = true
	player.sprite.modulate.a = 1.0
	gs.reset_to_new_game()
	await _frames(15)
	player.attack_timer = 10.0
	player.parry_timer = 10.0


func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1


## Waits (max_frames) until [param cond] is true. Returns the frame count, or -1 on timeout.
func _wait_until(cond: Callable, max_frames: int) -> int:
	var counted := 0
	while counted < max_frames:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1
		if cond.call():
			return counted
	return -1


# --- tests ---

func _test_forward_slash() -> void:
	await _reset(0.0)
	_spawn_dummy(Vector2(24.0, DUMMY_REST_Y))
	await _frames(10)
	var hp0: int = dummy.current_hp
	_act(&"attack", true)
	var f := await _wait_until(func() -> bool: return dummy.current_hp < hp0, 30)
	_act(&"attack", false)
	var vx: float = dummy.velocity.x
	var dhp: int = hp0 - dummy.current_hp
	var silk: int = gs.current_silk
	var pv: Vector2 = player.velocity
	await _frames(3)
	_add("forward slash: dummy hp", "%d -> %d (%d dmg) in %d frames" % [hp0, dummy.current_hp, dhp, f], "-4 (GameState.damage)", dhp == 4)
	_add("forward slash: silk", "%d" % silk, "+1", silk == 1)
	_add("forward slash: dummy knockback", "vx=%.1f px/s" % vx, "~+80 away from player", vx > 70.0 and vx <= 80.5,
			"after 1 drag tick")
	_add("forward slash: no player recoil", "player vel=(%.1f, %.1f)" % [pv.x, pv.y], "~0", pv.length() < 20.0)


func _test_forward_slash_left() -> void:
	await _reset(0.0)
	_act(&"move_left", true)
	await _frames(2)
	_act(&"move_left", false)
	await _frames(3)
	var px: float = player.global_position.x
	_spawn_dummy(Vector2(px - 24.0, DUMMY_REST_Y))
	await _frames(10)
	var hp0: int = dummy.current_hp
	_act(&"attack", true)
	var f := await _wait_until(func() -> bool: return dummy.current_hp < hp0, 30)
	_act(&"attack", false)
	_add("slash facing left hits dummy on the left", "hit after %d frames, dummy vx=%.1f" % [f, dummy.velocity.x],
			"hit, knocked left (vx<0)", f > 0 and dummy.velocity.x < -70.0, "mirrored Visual / negative scale")


func _test_up_slash() -> void:
	await _reset(0.0)
	_spawn_dummy(Vector2(0.0, REST_Y - 24.0 - 9.5), 0.0) # body centre 24 px above the player origin
	await _frames(10)
	var hp0: int = dummy.current_hp
	_act(&"move_up", true)
	await _frames(2)
	_act(&"attack", true)
	var f := await _wait_until(func() -> bool: return dummy.current_hp < hp0, 30)
	_act(&"attack", false)
	_act(&"move_up", false)
	_add("up slash hits dummy above", "dummy hp %d -> %d (%d frames)" % [hp0, dummy.current_hp, f], "-4", hp0 - dummy.current_hp == 4)


func _test_attack_cooldown() -> void:
	await _reset(0.0)
	_act(&"attack", true)
	await physics_frame
	_act(&"attack", false)
	var first: int = _slash_count()
	await _frames(14)
	_act(&"attack", true) # 0.25 s after the first press
	await physics_frame
	_act(&"attack", false)
	var at_025: int = _slash_count()
	await _frames(6)
	_act(&"attack", true) # 0.367 s after the first press
	await physics_frame
	_act(&"attack", false)
	var at_036: int = _slash_count()
	_add("attack cooldown", "slashes: t0=%d, +0.25s=%d, +0.37s=%d" % [first, at_025, at_036],
			"1, 1 (ignored), 2 (accepted)", first == 1 and at_025 == 1 and at_036 == 2,
			"0.2 s anim + 0.15 s cooldown")


func _test_pogo_enemy() -> void:
	await _reset(0.0)
	gs.extra_jump = 2
	_spawn_dummy(Vector2(0.0, DUMMY_REST_Y))
	# Start up-left of the dummy so the slash tip (player + (17, 23)) lands on its top after the diagonal dash.
	player.global_position = Vector2(-38.0, REST_Y - 40.0)
	player.velocity = Vector2.ZERO
	await _frames(1)
	player.dash_count = 0
	player.jump_count = 0
	var hp0: int = dummy.current_hp
	var silk0: int = gs.current_silk
	_act(&"move_down", true)
	await _frames(2)
	var in_air: bool = not player.is_grounded
	_act(&"attack", true)
	await physics_frame
	_act(&"attack", false)
	var best_vy := 0.0
	var impacted := false
	for i in 40:
		await physics_frame
		best_vy = minf(best_vy, player.velocity.y)
		if dummy.current_hp < hp0:
			impacted = true
		if impacted and i > 3 and player.velocity.y > best_vy + 100.0:
			break
	_act(&"move_down", false)
	var dash_ok: bool = player.dash_count == gs.max_dash
	var jump_ok: bool = player.jump_count == 2
	var no_dash: bool = not player.is_dashing
	_add("pogo onto dummy: impact + bounce", "airborne=%s, hit=%s, min vy=%.1f px/s" % [in_air, impacted, best_vy],
			"vy ~ -400 (dash_recoil)", in_air and impacted and best_vy <= -340.0 and best_vy >= -410.0)
	_add("pogo onto dummy: dash & jumps refilled", "dash=%d (max %d), jumps=%d (extra 2), dashing=%s" % [player.dash_count, gs.max_dash, player.jump_count, not no_dash],
			"refilled, dash ended", dash_ok and jump_ok and no_dash)
	_add("pogo onto dummy: dmg + silk", "dummy %d -> %d, silk %d -> %d" % [hp0, dummy.current_hp, silk0, gs.current_silk], "-4, +1",
			hp0 - dummy.current_hp == 4 and gs.current_silk == silk0 + 1)
	gs.extra_jump = 0


func _test_pogo_floor() -> void:
	await _reset(0.0)
	player.global_position = Vector2(0.0, REST_Y - 28.0)
	player.velocity = Vector2.ZERO
	await _frames(1)
	player.dash_count = 1
	_act(&"move_down", true)
	await _frames(2)
	_act(&"attack", true)
	await physics_frame
	_act(&"attack", false)
	var started: bool = player.is_dashing
	var f := await _wait_until(func() -> bool: return not player.is_dashing, 30)
	var speed: float = player.velocity.length()
	_act(&"move_down", false)
	_add("pogo into floor: dash stops on ground contact", "dashing started=%s, stopped after %d frames (%.2f s), speed %.1f" % [started, f, f / FPS, speed],
			"stops before dash_time 0.25 s, velocity ~0", started and f > 0 and f < 14 and speed < 30.0,
			"dash_attack_touch_ground")


func _test_damage() -> void:
	await _reset(0.0)
	var hp0: int = gs.current_hp
	var t0: int = Time.get_ticks_msec()
	player.damaged(1, Vector2.RIGHT)
	var hp1: int = gs.current_hp
	var scale_during: float = Engine.time_scale
	var iframe_now: bool = player.in_i_frame
	var lock_now: int = player.control_lock
	await physics_frame
	await _thaw()
	var real_ms: int = Time.get_ticks_msec() - t0
	var scale_after: float = Engine.time_scale
	var vel: Vector2 = player.velocity
	_add("damage: hp", "%d -> %d" % [hp0, hp1], "-1", hp1 == hp0 - 1)
	_add("damage: hit-stop", "time_scale %.1f during, %.1f after; %d ms real" % [scale_during, scale_after, real_ms],
			"0.0 for 0.35 s real, then 1.0", scale_during == 0.0 and scale_after == 1.0 and real_ms >= 330 and real_ms < 800)
	_add("damage: knockback (zero first, then impulse)", "vel=(%.1f, %.1f)" % [vel.x, vel.y], "(+80, -80) minus one tick of drag/gravity (77.4, -64.8): stun zeroes velocity BEFORE the impulse",
			vel.x > 74.0 and vel.x < 80.5 and vel.y < -60.0 and vel.y > -82.0)
	_add("damage: i-frames + stun start", "in_i_frame=%s, control_lock=%d, alpha=%.1f, hurtbox_monitoring=%s" % [iframe_now, lock_now, player.sprite.modulate.a, player.hurtbox.monitoring],
			"true, 1, 0.5, off", iframe_now and lock_now == 1 and absf(player.sprite.modulate.a - 0.5) < 0.01 and not player.hurtbox.monitoring)
	# Second hit inside the window is ignored.
	await _frames(10)
	player.damaged(1, Vector2.RIGHT)
	_add("damage: second hit inside i-frames ignored", "hp %d, time_scale %.1f" % [gs.current_hp, Engine.time_scale], "still %d, no new freeze" % (hp0 - 1),
			gs.current_hp == hp0 - 1 and Engine.time_scale == 1.0)
	# Stun / i-frame length in game frames since the freeze ended (10 frames already counted).
	var stun_f := await _wait_until(func() -> bool: return player.control_lock == 0, 60)
	var total_stun: int = 10 + stun_f
	_add("damage: stun length", "control released after %d game frames (%.2f s)" % [total_stun, total_stun / FPS], "0.4 s",
			absf(total_stun / FPS - 0.4) < 0.05 and not player.is_hurt)
	var iframe_f := await _wait_until(func() -> bool: return not player.in_i_frame, 120)
	var total_if: int = total_stun + iframe_f
	_add("damage: i-frame length", "ended after %d game frames (%.2f s), alpha %.1f, hurtbox on" % [total_if, total_if / FPS, player.sprite.modulate.a],
			"1.5 s, alpha back to 1", absf(total_if / FPS - 1.5) < 0.05 and player.sprite.modulate.a > 0.99)
	await _frames(3)
	player.damaged(1, Vector2.RIGHT)
	_add("damage: hit accepted after i-frames", "hp %d" % gs.current_hp, "%d" % (hp0 - 2), gs.current_hp == hp0 - 2)
	await _thaw()
	_add("damage: time_scale back to 1.0 after hit-stop", "%.1f" % Engine.time_scale, "1.0", Engine.time_scale == 1.0)


func _test_lifeblood() -> void:
	await _reset(0.0)
	gs.lifeblood_hp = 2
	var hp0: int = gs.current_hp
	player.damaged(1, Vector2.RIGHT)
	await physics_frame
	var lb_after_1: int = gs.lifeblood_hp
	var hp_after_1: int = gs.current_hp
	_add("lifeblood absorbs 1 damage", "lifeblood 2 -> %d, hp %d -> %d" % [lb_after_1, hp0, hp_after_1], "lifeblood 1, hp unchanged",
			lb_after_1 == 1 and hp_after_1 == hp0)
	await _reset(0.0)
	gs.lifeblood_hp = 1
	player.damaged(3, Vector2.RIGHT)
	await physics_frame
	_add("lifeblood partly absorbs 3 damage", "lifeblood 1 -> %d, hp %d -> %d" % [gs.lifeblood_hp, 5, gs.current_hp], "lifeblood 0, hp 3",
			gs.lifeblood_hp == 0 and gs.current_hp == 3)


func _test_parry() -> void:
	await _reset(0.0)
	var x0: float = player.global_position.x
	_act(&"parry", true)
	await physics_frame
	_act(&"parry", false)
	await _frames(6)
	var parrying: bool = player.is_parrying
	var hp0: int = gs.current_hp
	player.damaged(1, Vector2.LEFT)
	var hp_after: int = gs.current_hp
	var state_after: int = player.parry_state
	var t0: int = Time.get_ticks_msec()
	await physics_frame
	await _thaw()
	var freeze_ms: int = Time.get_ticks_msec() - t0
	await _frames(1)
	var dash_started: bool = player.is_dashing and player.in_attack and player.in_i_frame
	var peak: float = player.velocity.x
	var slash_pierce := false
	for c in player.visual.get_children():
		if c is Area2D and c.piercing and not c.has_recoil:
			slash_pierce = true
	var x_start: float = player.global_position.x
	await _frames(14)
	var dx: float = player.global_position.x - x_start
	await _frames(3)
	var dash_done: bool = not player.is_dashing and not player.in_attack and not player.is_parrying
	var iframe_tail: bool = player.in_i_frame
	await _frames(8)
	var iframe_end: bool = not player.in_i_frame
	var timer_ok: bool = absf(player.parry_timer - gs.parry_cooldown) < 0.5
	_act(&"parry", true)
	await physics_frame
	_act(&"parry", false)
	await physics_frame
	var again: bool = player.is_parrying
	_add("parry: damage inside window", "parrying=%s, hp %d -> %d, parry_state %d, freeze %d ms" % [parrying, hp0, hp_after, state_after, freeze_ms],
			"no hp loss, ParryReceived (2), 0.35 s freeze", parrying and hp_after == hp0 and state_after == 2 and freeze_ms >= 320 and freeze_ms < 800)
	_add("parry: riposte dash", "dash/attack/i-frame=%s, vx=%.0f, moved %.1f px in 0.25 s, piercing dash-slash=%s" % [dash_started, peak, dx, slash_pierce],
			"1.5x dash (480 px/s), forward, piercing no-recoil slash", dash_started and peak > 440.0 and dx > 60.0 and slash_pierce,
			"x moved %.1f px total" % (player.global_position.x - x0))
	_add("parry: riposte end + i-frame tail", "dash ended=%s, i-frame still on after dash=%s, i-frame ended=%s" % [dash_done, iframe_tail, iframe_end],
			"dash ends, +0.1 s i-frame tail, then off", dash_done and iframe_tail and iframe_end)
	_add("parry: available again right after", "parry_timer=%.2f (cooldown %.1f), re-parry started=%s" % [player.parry_timer, gs.parry_cooldown, again], "timer reset to cooldown, parries again",
			timer_ok and again)
	await _frames(20)


func _test_parry_late() -> void:
	await _reset(0.0)
	_act(&"parry", true)
	await physics_frame
	_act(&"parry", false)
	await _frames(20) # 0.33 s > parry_window 0.25
	var parrying: bool = player.is_parrying
	var hp0: int = gs.current_hp
	player.damaged(1, Vector2.LEFT)
	_add("parry: damage after the window", "parrying=%s, hp %d -> %d" % [parrying, hp0, gs.current_hp], "not parrying, -1 hp",
			not parrying and gs.current_hp == hp0 - 1)


func _test_contact() -> void:
	await _reset(0.0)
	_spawn_dummy(Vector2(70.0, DUMMY_REST_Y))
	await _frames(10)
	var hp0: int = gs.current_hp
	_act(&"move_right", true)
	var f := await _wait_until(func() -> bool: return gs.current_hp < hp0, 120)
	_act(&"move_right", false)
	var dummy_hp: int = dummy.current_hp
	_add("contact damage: walking into the dummy", "hp %d -> %d after %d frames" % [hp0, gs.current_hp, f], "-1", gs.current_hp == hp0 - 1 and dummy_hp == DUMMY_HP)
	# Stay inside: pin the player on the dummy; it must be hurt again once the i-frames end.
	await _thaw()
	var pin_x: float = dummy.global_position.x
	var game_frames: int = 0
	var hp1: int = gs.current_hp
	for i in 400:
		await physics_frame
		if Engine.time_scale > 0.0:
			game_frames += 1
		player.global_position = Vector2(pin_x, REST_Y)
		player.velocity = Vector2.ZERO
		if gs.current_hp < hp1:
			break
	_add("contact damage: staying inside hurts again after i-frames", "hp %d -> %d after %d game frames (%.2f s)" % [hp1, gs.current_hp, game_frames, game_frames / FPS],
			"~1.5 s (i-frame time)", gs.current_hp == hp1 - 1 and absf(game_frames / FPS - 1.5) < 0.15)
	await _thaw()


func _test_death() -> void:
	await _reset(0.0)
	gs.current_hp = 1
	died_count = 0
	var t0: int = Time.get_ticks_msec()
	player.damaged(1, Vector2.RIGHT)
	var dead_now: bool = player.is_dead
	var lock_now: int = player.control_lock
	var hp_now: int = gs.current_hp
	await _frames(30)
	var still_dead: bool = player.is_dead
	var hp_mid: int = gs.current_hp
	var f := await _wait_until(func() -> bool: return not player.is_dead, 120)
	var total: int = 30 + f
	_add("death: hp 0 -> respawn stub called, hp restored after transition_time",
			"dead=%s lock=%d hp=%d, died signals=%d; still dead at 0.5 s=%s (hp %d); restored after %d frames (%.2f s) to hp %d, lock %d" \
			% [dead_now, lock_now, hp_now, died_count, still_dead, hp_mid, total, total / FPS, gs.current_hp, player.control_lock],
			"dead, lock 1, died x1, restored after 1.0 s to max hp",
			dead_now and lock_now == 1 and hp_now == 0 and died_count == 1 and still_dead and hp_mid == 0 \
			and absf(total / FPS - 1.0) < 0.1 and gs.current_hp == gs.max_hp and player.control_lock == 0)
	player.is_kinematic = false


func _print_table() -> void:
	print("")
	print("=== P3 combat test (60 Hz physics) ===")
	for r: Array in rows:
		print("[%s] %-52s measured: %s | expected: %s%s" % [r[3], r[0], r[1], r[2], ("  (" + (r[4] as String) + ")") if (r[4] as String) != "" else ""])
	print("test_combat: ", "FAILED (%d)" % fails if fails > 0 else "ALL PASS")
