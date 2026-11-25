extends SceneTree
## Automated silk-skill + HUD test (plan P4). Flat constructed room with the real tileset, the real
## player scene, real training dummies and the real HUD scene. Simulates inputs and measures
## heal / gossamer / silk burst timings, costs, damage, interrupts and HUD state.
## Run: godot --headless --path . -s tools/test_silk.gd
## Physics runs at 60 Hz. Times are measured in un-frozen physics frames after the press (a hit-stop
## freeze keeps firing physics frames with delta 0, they are not counted). The press is consumed by
## the player on the first tick, so measured times carry about +-2 frames (+-0.033 s) of jitter.

const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const DUMMY_PATH := "res://scenes/enemies/training_dummy.tscn"
const HUD_PATH := "res://scenes/ui/hud.tscn"
const SOLID_ATLAS := Vector2i(3, 3)
const FLOOR_X := [-40, 40]
const FLOOR_Y := [0, 2]
const REST_Y := -14.3 # player origin standing on the floor (floor top at y = 0)
const DUMMY_REST_Y := -14.75 # dummy origin standing on the floor
const AIR_Y := -300.0 # high enough that nothing is hit during a 1 s cast
const DUMMY_HP := 999
const FPS := 60.0
const TOL := 0.06 # seconds

var player # untyped: class names / autoloads are not resolvable when this script is compiled
var gs # GameState autoload node
var dummy
var dummy2
var hud
var rows: Array = []
var fails: int = 0
var tilemap: TileMapLayer


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	_build_room()
	hud = (load(HUD_PATH) as PackedScene).instantiate()
	root.add_child(hud)
	player = (load(PLAYER_PATH) as PackedScene).instantiate()
	root.add_child(player)
	player.global_position = Vector2(0, REST_Y)
	await _frames(20)

	await _test_heal_air()
	await _test_heal_ground()
	await _test_heal_refused()
	await _test_gossamer()
	await _test_silk_burst(false)
	await _test_silk_burst(true)
	await _test_skill_blocked_in_attack()
	await _test_interrupt_heal()
	await _test_interrupt_gossamer()
	await _test_interrupt_burst()
	await _test_hud()

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


## Waits n un-frozen physics frames.
func _frames(n: int) -> void:
	var counted := 0
	while counted < n:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1


## Waits until a running hit-stop freeze is over.
func _thaw() -> void:
	var guard := 0
	while Engine.time_scale == 0.0 and guard < 600:
		await physics_frame
		guard += 1


func _act(action: StringName, pressed: bool, strength: float = 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = strength if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_all() -> void:
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"dash", &"attack", &"parry", &"silk_skill"]:
		if Input.is_action_pressed(a):
			_act(a, false)


## Presses the silk-skill button for one physics frame (like a tap).
func _tap_skill() -> void:
	_act(&"silk_skill", true)
	await physics_frame
	_act(&"silk_skill", false)


func _remove_dummies() -> void:
	for d in [dummy, dummy2]:
		if d != null and is_instance_valid(d):
			d.queue_free()
	dummy = null
	dummy2 = null


func _spawn_dummy(pos: Vector2) -> Node:
	var d = (load(DUMMY_PATH) as PackedScene).instantiate()
	d.position = pos
	root.add_child(d)
	return d


## Clears all transient state, puts the player at (x, y), resets GameState numbers.
func _reset(x: float = 0.0, y: float = REST_Y, facing_left: bool = false) -> void:
	_release_all()
	await _frames(3)
	await _thaw()
	_remove_dummies()
	Engine.time_scale = 1.0
	for n in player.visual.get_children():
		if n.name.begins_with("Gossamer") or n.name.begins_with("SilkBurst") or n.name.begins_with("SilkBind"):
			n.free()
	player.rest_chair_recovery()
	player.anim.stop()
	player.anim_override = &""
	player.in_silk_skill = false
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	player.is_dashing = false
	player.is_jumping = false
	player.is_dead = false
	player.is_kinematic = false
	player.control_lock = 0
	player.gravity_on = true
	player.in_attack = false
	player.is_facing_left = facing_left
	player.visual.scale.x = -1.0 if facing_left else 1.0
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
	player.velocity = Vector2.ZERO


func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1


func _near(a: float, b: float, tol: float = TOL) -> bool:
	return absf(a - b) <= tol


## Runs n un-frozen frames after the press and calls [param each] with the 1-based frame number.
func _run(n: int, each: Callable) -> void:
	var counted := 0
	while counted < n:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1
			each.call(counted)


# --- tests ---

func _test_heal_air() -> void:
	await _reset(0.0, AIR_Y)
	gs.current_silk = 8
	gs.current_hp = 3
	gs.stats_changed.emit()
	var y0: float = player.global_position.y
	await _tap_skill()
	var silk_now: int = gs.current_silk
	var s := {"t_heal": -1.0, "t_release": -1.0, "max_dy": 0.0, "max_speed": 0.0, "hp_before": 3, "lock_seen": false, "grav_off": true}
	await _run(90, func(f: int) -> void:
		var t: float = f / FPS
		if gs.current_hp > 3 and s["t_heal"] < 0.0:
			s["t_heal"] = t
		if player.in_silk_skill:
			s["lock_seen"] = true
			s["max_dy"] = maxf(s["max_dy"], absf(player.global_position.y - y0))
			s["max_speed"] = maxf(s["max_speed"], player.velocity.length())
			if player.gravity_on:
				s["grav_off"] = false
		if s["lock_seen"] and not player.in_silk_skill and s["t_release"] < 0.0:
			s["t_release"] = t
		if s["t_heal"] < 0.0 and t < 0.55:
			s["hp_before"] = gs.current_hp)
	_add("heal (air): silk paid at press", "silk 8 -> %d (immediately)" % silk_now, "0", silk_now == 0)
	_add("heal (air): hp +3 clamped at actual_heal", "hp 3 -> %d at %.3f s (hp before 0.55 s: %d)" % [gs.current_hp, s["t_heal"], s["hp_before"]],
			"5 at ~0.583 s, not before", gs.current_hp == 5 and s["hp_before"] == 3 and _near(s["t_heal"], 0.5833))
	_add("heal (air): lock released by end_heal", "released at %.3f s, gravity_on=%s" % [s["t_release"], player.gravity_on],
			"~1.0 s, gravity back on", s["lock_seen"] and _near(s["t_release"], 1.0) and player.gravity_on)
	_add("heal (air): did not fall while casting", "max dy %.2f px, max speed %.1f px/s, gravity off during cast: %s" % [s["max_dy"], s["max_speed"], s["grav_off"]],
			"~0 px (lock: velocity 0, gravity off)", s["max_dy"] < 1.0 and s["max_speed"] < 1.0 and s["grav_off"])
	_add("heal: SilkBind VFX spawned + freed", "SilkBind nodes left under Visual: %d" % _count_binds(), "0 after 0.6 s", _count_binds() == 0)
	_add("heal: flash white", "hp flash stopped, flash param %.1f" % player._flash_material.get_shader_parameter("flash"), "0.0 after 0.25 s",
			player._flash_material.get_shader_parameter("flash") == 0.0)


func _count_binds() -> int:
	var n := 0
	for c in player.visual.get_children():
		if c.name.begins_with("SilkBind"):
			n += 1
	return n


func _test_heal_ground() -> void:
	await _reset(0.0)
	gs.current_silk = 8
	gs.current_hp = 4
	await _tap_skill()
	var s := {"hp": -1, "t": -1.0}
	await _run(90, func(f: int) -> void:
		if gs.current_hp != 4 and s["t"] < 0.0:
			s["t"] = f / FPS
			s["hp"] = gs.current_hp)
	_add("heal (ground): hp clamped to max", "hp 4 -> %d" % s["hp"], "5 (min(4+3, 5))", s["hp"] == 5)


func _test_heal_refused() -> void:
	await _reset(0.0)
	gs.current_silk = 8
	gs.current_hp = gs.max_hp
	await _tap_skill()
	await _frames(5)
	_add("heal refused at full hp", "silk %d, in_silk_skill=%s, clip '%s'" % [gs.current_silk, player.in_silk_skill, player.anim_override],
			"silk stays 8, no cast", gs.current_silk == 8 and not player.in_silk_skill and player.anim_override == &"")
	await _frames(70)
	await _reset(0.0)
	gs.current_silk = 7
	gs.current_hp = 3
	await _tap_skill()
	await _frames(5)
	_add("heal refused with silk < 8", "silk %d, hp %d, in_silk_skill=%s" % [gs.current_silk, gs.current_hp, player.in_silk_skill],
			"silk stays 7, hp 3, no cast", gs.current_silk == 7 and gs.current_hp == 3 and not player.in_silk_skill)
	await _reset(0.0)
	gs.current_silk = 5
	gs.current_hp = 3
	_act(&"move_up", true)
	await _frames(2)
	await _tap_skill()
	await _frames(5)
	_add("gossamer refused with silk 5 (Up held)", "silk %d, in_silk_skill=%s" % [gs.current_silk, player.in_silk_skill],
			"silk stays 5, no cast (needs 6; heal needs 8)", gs.current_silk == 5 and not player.in_silk_skill)
	_act(&"move_up", false)
	await _reset(0.0)
	gs.current_silk = 3
	_act(&"move_down", true)
	await _frames(2)
	await _tap_skill()
	await _frames(5)
	_add("silk burst refused with silk 3 (Down held)", "silk %d, in_silk_skill=%s" % [gs.current_silk, player.in_silk_skill],
			"silk stays 3, no cast (needs 4)", gs.current_silk == 3 and not player.in_silk_skill)
	_act(&"move_down", false)


func _test_gossamer() -> void:
	await _reset(0.0)
	gs.current_silk = 6
	dummy = _spawn_dummy(Vector2(24.0, DUMMY_REST_Y)) # inside the 38.4 px circle around (4, player y)
	dummy2 = _spawn_dummy(Vector2(100.0, DUMMY_REST_Y)) # outside
	await _frames(10)
	var hp0: int = dummy.current_hp
	var hp2: int = dummy2.current_hp
	_act(&"move_up", true)
	await _frames(2)
	await _tap_skill()
	var silk_now: int = gs.current_silk
	var s := {"ticks": [], "last": hp0, "max_silk": gs.current_silk, "t_free": -1.0, "t_release": -1.0, "lock": false, "seen_instance": false, "dy": 0.0}
	var y0: float = player.global_position.y
	await _run(80, func(f: int) -> void:
		var t: float = f / FPS
		if dummy.current_hp < s["last"]:
			s["ticks"].append([t, s["last"] - dummy.current_hp])
			s["last"] = dummy.current_hp
		s["max_silk"] = maxi(s["max_silk"], gs.current_silk)
		if is_instance_valid(player.gossamer_instance):
			s["seen_instance"] = true
		elif s["seen_instance"] and s["t_free"] < 0.0:
			s["t_free"] = t
		if player.in_silk_skill:
			s["lock"] = true
			s["dy"] = maxf(s["dy"], absf(player.global_position.y - y0))
		if s["lock"] and not player.in_silk_skill and s["t_release"] < 0.0:
			s["t_release"] = t)
	_act(&"move_up", false)
	var total: int = hp0 - dummy.current_hp
	var times: Array = []
	var all_three := true
	for tk: Array in s["ticks"]:
		times.append("%.2f" % tk[0])
		if tk[1] != 3:
			all_three = false
	_add("gossamer: Up+Q pays 6 silk at press", "silk 6 -> %d" % silk_now, "0", silk_now == 0)
	_add("gossamer: dummy inside radius damaged in ticks of 3", "%d ticks, total %d, at t = %s" % [s["ticks"].size(), total, ", ".join(times)],
			"3 per tick; Unity Update-timer gives a tick every >0.1 s -> 6-7 ticks (18-21)", all_three and total >= 18 and total <= 21,
			"strict `timer > 0.1` + reset to 0 at 60 fps = every 7 frames (0.117 s) -> 6 ticks / 18, plan said ~7 / 21")
	_add("gossamer: dummy outside radius untouched", "hp %d -> %d" % [hp2, dummy2.current_hp], "unchanged", dummy2.current_hp == hp2)
	_add("gossamer: gives no silk", "max silk seen %d, final %d" % [s["max_silk"], gs.current_silk], "0", s["max_silk"] == 0 and gs.current_silk == 0)
	_add("gossamer: instance freed after 0.75 s", "freed at %.3f s" % s["t_free"], "~0.75 s", s["seen_instance"] and _near(s["t_free"], 0.75, 0.08))
	_add("gossamer: lock released by end_heal, no fall", "released at %.3f s, dy %.2f px, gravity_on %s" % [s["t_release"], s["dy"], player.gravity_on],
			"~1.0 s, 0 px", _near(s["t_release"], 1.0) and s["dy"] < 1.0 and player.gravity_on)


func _test_silk_burst(left: bool) -> void:
	var side: float = -1.0 if left else 1.0
	await _reset(0.0, REST_Y, left)
	gs.current_silk = 4
	dummy = _spawn_dummy(Vector2(64.0 * side, DUMMY_REST_Y))
	await _frames(10)
	var hp0: int = dummy.current_hp
	_act(&"move_down", true)
	await _frames(2)
	await _tap_skill()
	var silk_now: int = gs.current_silk
	var s := {"t_hit": -1.0, "hits": 0, "last": hp0, "v_hit": Vector2.ZERO, "t_recoil": -1.0, "v_recoil": Vector2.ZERO, "t_release": -1.0,
			"lock": false, "prev_vx": player.velocity.x, "max_silk": gs.current_silk, "t_free": -1.0, "seen": false}
	await _run(80, func(f: int) -> void:
		var t: float = f / FPS
		if dummy.current_hp < s["last"]:
			s["hits"] += 1
			s["t_hit"] = t if s["t_hit"] < 0.0 else s["t_hit"]
			s["v_hit"] = dummy.velocity
			s["last"] = dummy.current_hp
		var vx: float = player.velocity.x
		if s["t_recoil"] < 0.0 and absf(vx - s["prev_vx"]) > 100.0:
			s["t_recoil"] = t
			s["v_recoil"] = player.velocity
		s["prev_vx"] = vx
		s["max_silk"] = maxi(s["max_silk"], gs.current_silk)
		if is_instance_valid(player.silk_burst_instance):
			s["seen"] = true
		elif s["seen"] and s["t_free"] < 0.0:
			s["t_free"] = t
		if player.in_silk_skill:
			s["lock"] = true
		if s["lock"] and not player.in_silk_skill and s["t_release"] < 0.0:
			s["t_release"] = t)
	_act(&"move_down", false)
	var dmg: int = hp0 - dummy.current_hp
	var tag: String = "left" if left else "right"
	_add("silk burst (%s): Down+Q pays 4 silk at press" % tag, "silk 4 -> %d" % silk_now, "0", silk_now == 0)
	_add("silk burst (%s): dummy 64 px ahead takes 10, once" % tag, "damage %d in %d hit(s), first at %.3f s" % [dmg, s["hits"], s["t_hit"]],
			"10 once; hitbox enabled 0.15 s after the throw (0.167 + 0.15 = 0.317 s)", dmg == 10 and s["hits"] == 1 and _near(s["t_hit"], 0.3167, 0.08))
	var vh: Vector2 = s["v_hit"]
	_add("silk burst (%s): knockback (dir.x * 240, -80)" % tag, "dummy vel (%.1f, %.1f) on the hit frame" % [vh.x, vh.y],
			"vx ~ %+d, vy ~ -80 (minus one tick of gravity/drag)" % int(240 * side), vh.x * side > 200.0 and vh.x * side < 245.0 and vh.y < -60.0 and vh.y > -82.0)
	var vr: Vector2 = s["v_recoil"]
	_add("silk burst (%s): recoil impulse at 0.833 s" % tag, "at %.3f s, player vel (%.1f, %.1f)" % [s["t_recoil"], vr.x, vr.y],
			"vx ~ %+d, vy ~ -32 at ~0.833 s" % int(-160 * side), _near(s["t_recoil"], 0.8333) and vr.x * side < -140.0 and vr.x * side > -165.0)
	_add("silk burst (%s): lock released by end_heal" % tag, "at %.3f s, gravity_on %s" % [s["t_release"], player.gravity_on],
			"~0.967 s", _near(s["t_release"], 0.9667) and player.gravity_on)
	_add("silk burst (%s): no silk gained, instance freed" % tag, "max silk %d, freed at %.3f s" % [s["max_silk"], s["t_free"]],
			"0; instance lives 0.483 s after the throw (0.167 + 0.483 = 0.65 s)", s["max_silk"] == 0 and s["seen"] and _near(s["t_free"], 0.65, 0.08))


func _test_skill_blocked_in_attack() -> void:
	await _reset(0.0)
	gs.current_silk = 8
	gs.current_hp = 3
	player.in_attack = true
	await _tap_skill()
	await _frames(3)
	_add("skill blocked while in_attack", "silk %d, in_silk_skill=%s" % [gs.current_silk, player.in_silk_skill], "silk stays 8, no cast",
			gs.current_silk == 8 and not player.in_silk_skill)
	player.in_attack = false
	await _reset(0.0)
	gs.current_silk = 8
	gs.current_hp = 3
	player.control_lock = 1
	await _tap_skill()
	await _frames(3)
	_add("skill blocked by the control gate (control_lock)", "silk %d, in_silk_skill=%s" % [gs.current_silk, player.in_silk_skill], "silk stays 8, no cast",
			gs.current_silk == 8 and not player.in_silk_skill)
	player.control_lock = 0


func _test_interrupt_heal() -> void:
	await _reset(0.0, AIR_Y)
	gs.current_silk = 8
	gs.current_hp = 3
	await _tap_skill()
	await _frames(18) # ~0.3 s, before actual_heal
	var locked_before: bool = player.in_silk_skill
	player.damaged(1, Vector2.LEFT)
	var hp_hit: int = gs.current_hp
	var lock_after: bool = player.in_silk_skill
	await _thaw()
	await _frames(100) # past 0.583 s / 1.0 s / stun / i-frames
	_add("interrupt heal: hit before actual_heal", "locked before=%s; hp 3 -> %d after hit, %d after 1.7 s; in_silk_skill %s -> %s, gravity_on %s, clip '%s'" % [
			locked_before, hp_hit, gs.current_hp, lock_after, player.in_silk_skill, player.gravity_on, player.anim_override],
			"hp 2 and stays 2 (no late heal), lock released at once, gravity on",
			locked_before and hp_hit == 2 and gs.current_hp == 2 and not lock_after and not player.in_silk_skill and player.gravity_on and player.anim_override == &"")


func _test_interrupt_gossamer() -> void:
	await _reset(0.0)
	gs.current_silk = 6
	_act(&"move_up", true)
	await _frames(2)
	await _tap_skill()
	_act(&"move_up", false)
	await _frames(18)
	var alive: bool = is_instance_valid(player.gossamer_instance)
	player.damaged(1, Vector2.LEFT)
	await _thaw()
	await _frames(2)
	var gone: bool = not is_instance_valid(player.gossamer_instance)
	await _frames(70)
	_add("interrupt gossamer: instance freed, lock released", "alive before=%s, freed after hit=%s, in_silk_skill=%s, gravity_on=%s" % [alive, gone, player.in_silk_skill, player.gravity_on],
			"freed, lock released", alive and gone and not player.in_silk_skill and player.gravity_on)


func _test_interrupt_burst() -> void:
	await _reset(0.0)
	gs.current_silk = 4
	_act(&"move_down", true)
	await _frames(2)
	await _tap_skill()
	_act(&"move_down", false)
	await _frames(30) # 0.5 s: burst thrown (0.167 s), recoil still to come (0.833 s)
	var alive: bool = is_instance_valid(player.silk_burst_instance)
	player.damaged(1, Vector2.ZERO)
	await _thaw()
	await _frames(2)
	var gone: bool = not is_instance_valid(player.silk_burst_instance)
	var vmax := {"vx": 0.0}
	await _run(60, func(_f: int) -> void:
		vmax["vx"] = maxf(vmax["vx"], absf(player.velocity.x)))
	var vx_max: float = vmax["vx"]
	_add("interrupt silk burst: instance freed, no late recoil", "alive before=%s, freed=%s, max |vx| afterwards %.1f, in_silk_skill=%s" % [alive, gone, vx_max, player.in_silk_skill],
			"freed, no recoil impulse (|vx| < 100), lock released", alive and gone and vx_max < 100.0 and not player.in_silk_skill)


func _test_hud() -> void:
	await _reset(0.0)
	await _frames(2)
	var full: Texture2D = hud.mask_full
	var empty: Texture2D = hud.mask_empty
	_add("HUD initial: masks / silk / shards", "masks %d (container %d), silk %d (container %d), shards '%s'" % [
			hud.masks.size(), hud.masks_box.get_child_count(), hud.silk_segments.size(), hud.silk_box.get_child_count(), hud.shard_count.text],
			"5 masks (all full), 8 silk (all empty), '0'",
			hud.masks.size() == 5 and hud.masks_box.get_child_count() == 5 and _masks_match(5, 0) and hud.silk_segments.size() == 8 and _silk_match(0) and hud.shard_count.text == "0")
	# damage
	player.damaged(2, Vector2.LEFT)
	await _thaw()
	_add("HUD after damage 2", "hp %d -> full masks %d" % [gs.current_hp, _count_tex(hud.masks, full)], "hp 3: 3 full, 2 empty", gs.current_hp == 3 and _masks_match(5, 0))
	# silk
	gs.add_silk(3)
	_add("HUD after silk +3", "silk %d -> filled %d of %d" % [gs.current_silk, _count_tex(hud.silk_segments, hud.silk_filled), hud.silk_segments.size()],
			"3 filled, 5 empty", _silk_match(0) and _count_tex(hud.silk_segments, hud.silk_filled) == 3)
	# heal
	player.heal(2)
	_add("HUD after heal +2", "hp %d -> full masks %d" % [gs.current_hp, _count_tex(hud.masks, full)], "hp 5: 5 full", gs.current_hp == 5 and _masks_match(5, 0))
	# silk spent by a skill
	gs.current_silk = 8
	gs.stats_changed.emit()
	gs.add_silk(-6)
	_add("HUD after silk spent (-6)", "silk %d -> filled %d" % [gs.current_silk, _count_tex(hud.silk_segments, hud.silk_filled)], "2 filled", _silk_match(0) and gs.current_silk == 2)
	# lifeblood
	gs.add_lifeblood(1)
	var last: TextureRect = hud.masks[hud.masks.size() - 1]
	_add("HUD after lifeblood +1", "masks %d (container %d), last tint %s, texture full=%s" % [hud.masks.size(), hud.masks_box.get_child_count(), last.modulate, last.texture == full],
			"6 masks, last one tinted (0, 0.75, 1)", hud.masks.size() == 6 and hud.masks_box.get_child_count() == 6 and last.modulate.is_equal_approx(Color(0, 0.75, 1)) and last.texture == full and _masks_match(5, 1))
	# lifeblood absorbs the next hit, hp untouched
	await _frames(100) # i-frames from the earlier hit
	player.damaged(1, Vector2.LEFT)
	await _thaw()
	_add("HUD after lifeblood absorbs a hit", "hp %d, lifeblood %d, masks %d" % [gs.current_hp, gs.lifeblood_hp, hud.masks.size()], "hp 5, 5 masks (all full, no blue)",
			gs.current_hp == 5 and gs.lifeblood_hp == 0 and hud.masks.size() == 5 and _masks_match(5, 0))
	# shards
	gs.add_copper_shard(7)
	_add("HUD after copper shards +7", "label '%s'" % hud.shard_count.text, "'7'", hud.shard_count.text == "7")
	# max values
	gs.max_hp = 7
	gs.max_silk = 10
	gs.stats_changed.emit()
	_add("HUD after max_hp 7 / max_silk 10", "masks %d, silk %d (containers %d / %d)" % [hud.masks.size(), hud.silk_segments.size(), hud.masks_box.get_child_count(), hud.silk_box.get_child_count()],
			"7 masks (5 full, 2 empty), 10 silk segments", hud.masks.size() == 7 and hud.silk_segments.size() == 10 and hud.silk_box.get_child_count() == 10 and _masks_match(7, 0))
	gs.max_hp = 5
	gs.max_silk = 8
	gs.reset_to_new_game()
	_add("HUD after new game reset", "masks %d, silk %d, filled %d, shards '%s'" % [hud.masks.size(), hud.silk_segments.size(), _count_tex(hud.silk_segments, hud.silk_filled), hud.shard_count.text],
			"5 masks, 8 silk empty, '0'", hud.masks.size() == 5 and hud.silk_segments.size() == 8 and _silk_match(0) and hud.shard_count.text == "0")


## True when the first current_hp masks are full and the rest of the max_hp masks empty, and the
## lifeblood masks (count [param lifeblood]) are tinted.
func _masks_match(max_hp: int, lifeblood: int) -> bool:
	if hud.masks.size() != max_hp + lifeblood:
		return false
	for i in max_hp:
		var want: Texture2D = hud.mask_full if i < gs.current_hp else hud.mask_empty
		if hud.masks[i].texture != want:
			return false
	for i in lifeblood:
		if not hud.masks[max_hp + i].modulate.is_equal_approx(Color(0, 0.75, 1)):
			return false
	return true


func _silk_match(_unused: int) -> bool:
	for i in hud.silk_segments.size():
		var want: Texture2D = hud.silk_filled if i < gs.current_silk else hud.silk_empty
		if hud.silk_segments[i].texture != want:
			return false
	return true


func _count_tex(list: Array, tex: Texture2D) -> int:
	var n := 0
	for r in list:
		if r.texture == tex:
			n += 1
	return n


func _print_table() -> void:
	print("")
	print("=== P4 silk skills + HUD test (60 Hz physics) ===")
	for r: Array in rows:
		print("[%s] %-56s measured: %s | expected: %s%s" % [r[3], r[0], r[1], r[2], ("  (" + (r[4] as String) + ")") if (r[4] as String) != "" else ""])
	print("test_silk: ", "FAILED (%d)" % fails if fails > 0 else "ALL PASS")
