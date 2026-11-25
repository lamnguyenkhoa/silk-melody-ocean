extends SceneTree
## Automated enemy test (plan P5). Flat constructed room (real tileset), the real player scene and
## the real Crawling / Dipsa / Crabber / bullet / loot scenes; plus a smoke run of DirtCave1 / DirtCave2.
## Run: godot --headless --path . -s tools/test_enemies.gd
## Physics runs at 60 Hz. While a hit-stop freeze is active (Engine.time_scale 0) physics frames
## still fire, so _frames() counts only un-frozen frames ("game frames"). Death slow-motion (0.2 s of
## time_scale 0.2) is waited out with _settle() before any timing measurement.

const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const CRAWLING_PATH := "res://scenes/enemies/crawling.tscn"
const DIPSA_PATH := "res://scenes/enemies/dipsa.tscn"
const CRABBER_PATH := "res://scenes/enemies/crabber.tscn"
const BULLET_PATH := "res://scenes/enemies/projectile.tscn"
const LOOT_PATH := "res://scenes/loot/loot.tscn"
const SOLID_ATLAS := Vector2i(3, 3)
const FLOOR_X := [-30, 30]    # tiles: px -480 .. 496
const FLOOR_Y := [0, 2]
const WALL_TILE_X := 9        # wall column px 144 .. 160, rows -6 .. -1
const REST_Y := -14.3         # player origin standing on the floor (floor top at y = 0)
const FPS := 60.0
const UNITY_G := 9.81 * 16.0
const LAYER_DEAD_ENEMY := 64

var player # untyped: class names / autoloads are not resolvable when this script is compiled
var gs
var rows: Array = []
var fails: int = 0
var tilemap: TileMapLayer
var _hurt_frames: Array = []


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	_build_room()
	player = (load(PLAYER_PATH) as PackedScene).instantiate()
	root.add_child(player)
	player.global_position = Vector2(0, REST_Y)
	await _frames(20)

	await _test_crawling_speed()
	await _test_crawling_ledge()
	await _test_crawling_wall()
	await _test_crawling_contact()
	await _test_crawling_slash_death_loot()
	await _test_dipsa_alert()
	await _test_dipsa_steer()
	await _test_dipsa_shooting()
	await _test_bullet_cases()
	await _test_dipsa_slash_death()
	await _test_crabber_alert_walk()
	await _test_crabber_attack()
	await _test_crabber_slash_death()
	await _test_loot()
	await _test_room_smoke(1)
	await _test_room_smoke(2)

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
	for y in range(-6, 0):
		tilemap.set_cell(Vector2i(WALL_TILE_X, y), 0, SOLID_ATLAS)


## Waits n un-frozen physics frames.
func _frames(n: int) -> void:
	var counted := 0
	while counted < n:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1


## Waits until the hit-stop / death slow-motion is over (time_scale back to 1).
func _settle() -> void:
	var guard := 0
	while not is_equal_approx(Engine.time_scale, 1.0) and guard < 900:
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
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"dash", &"attack", &"parry"]:
		if Input.is_action_pressed(a):
			_act(a, false)


func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1


func _clear_world() -> void:
	for group: StringName in [&"enemies", &"loot", &"projectiles"]:
		for n in get_nodes_in_group(group):
			n.queue_free()


## Clears enemies / loot / bullets and puts the player on the floor at x; resets GameState numbers.
func _reset(x: float = 0.0) -> void:
	_release_all()
	await _frames(3)
	await _settle()
	_clear_world()
	Engine.time_scale = 1.0
	player.rest_chair_recovery()
	player.anim.stop()
	player.anim_override = &""
	player.global_position = Vector2(x, REST_Y)
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
	player.in_i_frame = false
	player.sprite.modulate.a = 1.0
	gs.reset_to_new_game()
	await _frames(15)
	player.attack_timer = 10.0
	player.parry_timer = 10.0


func _spawn(path: String, pos: Vector2, props: Dictionary = {}) -> Node2D:
	var e := (load(path) as PackedScene).instantiate() as Node2D
	e.position = pos
	for k: String in props:
		e.set(k, props[k])
	root.add_child(e)
	return e


func _wait_until(cond: Callable, max_frames: int) -> int:
	var counted := 0
	while counted < max_frames:
		await physics_frame
		if Engine.time_scale > 0.0:
			counted += 1
		if cond.call():
			return counted
	return -1


## Presses attack once (player facing right); returns once the slash was started.
func _slash() -> void:
	player.attack_timer = 10.0
	_act(&"attack", true)
	await physics_frame
	_act(&"attack", false)


# --- Crawling ---

func _test_crawling_speed() -> void:
	await _reset(-400.0)
	var c := _spawn(CRAWLING_PATH, Vector2(-100.0, -5.0))
	await _frames(240) # settle; patrol (speed measured while walking left, mid floor)
	var x0: float = c.global_position.x
	var moving_left: bool = not c.is_moving_right
	await _frames(60)
	var speed: float = absf(c.global_position.x - x0) # px in 1 s
	var k: float = -log(1.0 - c.lerp_weight) / c.lerp_step
	var expected: float = (k * c.speed - c.friction * UNITY_G * c.gravity_scale) / (k + c.drag)
	var on_floor: bool = c.is_on_floor()
	_add("crawling: steady patrol speed", "%.1f px/s (commanded %.0f), on_floor=%s, left=%s" % [speed, c.speed, on_floor, moving_left],
			"%.1f = (k*48 - mu*g)/(k+drag), Unity lerp + friction 0.4" % expected,
			absf(speed - expected) < 3.0 and on_floor and moving_left,
			"plan 6.2 said 48 px/s; Unity ground friction lowers it")
	_add("crawling: stats", "hp %d, type %d, drop %d, gravity %.1f, drag %.1f" % [c.max_hp, c.enemy_type, c.drop_amount, c.gravity_scale, c.drag],
			"8, 0, 3, 1, 1", c.max_hp == 8 and c.enemy_type == 0 and c.drop_amount == 3 and c.gravity_scale == 1.0 and c.drag == 1.0)


func _test_crawling_ledge() -> void:
	await _reset(-400.0)
	# Floor ends at px -480; the crawler starts 40 px from the ledge walking left.
	var c := _spawn(CRAWLING_PATH, Vector2(-440.0, -5.0))
	await _frames(20)
	var min_x: float = c.global_position.x
	var min_y_ok := true
	var turned_at := -1.0
	var frames_to_turn := -1
	for i in 600:
		await _frames(1)
		min_x = minf(min_x, c.global_position.x)
		if c.global_position.y > 8.0:
			min_y_ok = false
		if turned_at == -1.0 and c.is_moving_right:
			turned_at = c.global_position.x
			frames_to_turn = i
		if turned_at != -1.0 and i > frames_to_turn + 120:
			break
	var facing_right: bool = c.visual.scale.x < 0.0
	_add("crawling: turns around at a ledge", "turned at x=%.1f (floor edge -480, probe 12.4 ahead), min x=%.1f, never fell=%s, facing right=%s" % [turned_at, min_x, min_y_ok, facing_right],
			"turns ~12 px before the edge, stays on the floor, flips sprite", turned_at > -480.0 and turned_at < -440.0 and min_y_ok and facing_right and c.global_position.x > turned_at)


func _test_crawling_wall() -> void:
	await _reset(-400.0)
	# Wall column starts at px 144. Crawler at 100 walking right.
	var c := _spawn(CRAWLING_PATH, Vector2(100.0, -5.0), {"is_moving_right": true})
	await _frames(20)
	var max_x: float = c.global_position.x
	var turned_at := -1.0
	var f_turn := -1
	for i in 600:
		await _frames(1)
		max_x = maxf(max_x, c.global_position.x)
		if turned_at == -1.0 and not c.is_moving_right:
			turned_at = c.global_position.x
			f_turn = i
		if turned_at != -1.0 and i > f_turn + 90:
			break
	var body_edge: float = max_x + 9.1
	_add("crawling: turns around at a wall", "turned at x=%.1f, max x=%.1f (body edge %.1f vs wall 144), now moving left=%s, x=%.1f" % [turned_at, max_x, body_edge, not c.is_moving_right, c.global_position.x],
			"turns before touching the wall, then walks away", turned_at > 0.0 and body_edge < 144.0 and not c.is_moving_right and c.global_position.x < turned_at)


func _test_crawling_contact() -> void:
	await _reset(0.0)
	var hp0: int = gs.current_hp
	var c := _spawn(CRAWLING_PATH, Vector2(70.0, -5.0))
	var f := await _wait_until(func() -> bool: return gs.current_hp < hp0, 400)
	_add("crawling: contact damage", "hp %d -> %d after %d frames (%.2f s)" % [hp0, gs.current_hp, f, f / FPS],
			"-1 when the crawler walks into the player", f > 0 and gs.current_hp == hp0 - 1)
	c.queue_free()


func _kill_by_slash_and_check(path: String, pos: Vector2, label: String, hp: int, drop: int, type: int, pre_wait: int = 20, props: Dictionary = {}) -> void:
	await _reset(0.0)
	var e := _spawn(path, pos, props)
	await _frames(pre_wait)
	var hp0: int = e.current_hp
	var silk0: int = gs.current_silk
	await _slash()
	var f := await _wait_until(func() -> bool: return e.current_hp < hp0, 30)
	var dhp: int = hp0 - e.current_hp
	_add("%s: hurt by player slash" % label, "hp %d -> %d in %d frames, silk +%d, knockback vx=%.1f" % [hp0, e.current_hp, f, gs.current_silk - silk0, e.velocity.x],
			"-4 (GameState.damage), silk +1, knocked away", dhp == 4 and gs.current_silk == silk0 + 1 and e.velocity.x > 20.0)
	_add("%s: hp / stats" % label, "max_hp %d, drop %d, type %d" % [e.max_hp, e.drop_amount, e.enemy_type], "%d, %d, %d" % [hp, drop, type],
			e.max_hp == hp and e.drop_amount == drop and e.enemy_type == type)
	# Finish it off with direct damage (the first slash knocked it out of reach).
	var kills0: int = int(gs.world.enemy_kill_count.get(type, 0))
	await _frames(6) # past the 0.05 s invulnerability window
	var shards0: int = gs.copper_shard
	e.damaged(999, Vector2.ZERO)
	await _frames(3)
	var loot_nodes: Array = get_nodes_in_group("loot")
	_add("%s: death" % label, "is_dead=%s, layer=%d, contact monitorable=%s, kills %d -> %d, loot nodes=%d" % [e.is_dead, e.collision_layer, e.contact_area.monitorable, kills0, int(gs.world.enemy_kill_count.get(type, 0)), loot_nodes.size()],
			"dead, DeadEnemy layer (64), contact off, kill count +1, %d loot" % drop,
			e.is_dead and e.collision_layer == LAYER_DEAD_ENEMY and not e.contact_area.monitorable \
			and int(gs.world.enemy_kill_count.get(type, 0)) == kills0 + 1 and loot_nodes.size() == drop)
	await _settle()
	# Corpse must not hurt, and must keep falling to the floor (gravity 1) rather than patrolling.
	await _frames(120)
	var y_ok: bool = e.global_position.y < 12.0 # not through the floor top (floor surface y = 0)
	# Pick the loot up: walk the player's PlayerTrigger over every shard.
	var hp_before: int = gs.current_hp
	for l: Node2D in get_nodes_in_group("loot"):
		player.global_position = Vector2(l.global_position.x, REST_Y)
		player.velocity = Vector2.ZERO
		await _frames(4)
	await _frames(2)
	_add("%s: loot pickup" % label, "copper %d -> %d, corpse y=%.1f, player hp %d -> %d" % [shards0, gs.copper_shard, e.global_position.y, hp_before, gs.current_hp],
			"+%d copper shards, corpse rests on the floor, no damage from the corpse" % drop,
			gs.copper_shard == shards0 + drop and y_ok and gs.current_hp == hp_before)


func _test_crawling_slash_death_loot() -> void:
	# Walking away from the player (right) so it does not touch the player before the slash.
	await _kill_by_slash_and_check(CRAWLING_PATH, Vector2(24.0, -5.0), "crawling", 8, 3, 0, 20, {"is_moving_right": true})


# --- Dipsa ---

func _test_dipsa_alert() -> void:
	await _reset(0.0)
	var d := _spawn(DIPSA_PATH, Vector2(200.0, REST_Y - 20.0))
	await _frames(60)
	var idle_ok: bool = not d.alerted and d.velocity.length() < 0.01 and d.global_position.x == 200.0
	player.global_position = Vector2(60.0, REST_Y)
	await _frames(3)
	var alerted: bool = d.alerted
	player.global_position = Vector2(-300.0, REST_Y) # leaving does not un-alert
	await _frames(30)
	_add("dipsa: idle until the player is within 160 px", "idle at 200 px=%s, alerted at 140 px=%s, still alerted after the player left=%s" % [idle_ok, alerted, d.alerted],
			"idle, alerted, stays alerted", idle_ok and alerted and d.alerted)
	_add("dipsa: stats", "hp %d, type %d, drop %d, gravity %.1f, drag %.1f, detection %.0f" % [d.max_hp, d.enemy_type, d.drop_amount, d.gravity_scale, d.drag, d.detection_radius],
			"8, 1, 5, 0, 1.5, 160", d.max_hp == 8 and d.enemy_type == 1 and d.drop_amount == 5 and d.gravity_scale == 0.0 and d.drag == 1.5 and d.detection_radius == 160.0)


func _test_dipsa_steer() -> void:
	await _reset(0.0)
	player.is_kinematic = true
	player.global_position = Vector2(900.0, REST_Y - 100.0)
	var d := _spawn(DIPSA_PATH, Vector2(100.0, REST_Y - 100.0), {"alerted": true})
	await _frames(60)
	var v1: float = d.velocity.x
	var flipped_right: bool = d.visual.scale.x < 0.0
	await _frames(240)
	var vmax: float = d.velocity.x
	# Discrete model: a/drag * (1 - exp(-drag * t)) at t = 1 s.
	var expected1: float = d.move_acceleration / d.drag * (1.0 - exp(-d.drag * 1.0))
	var top: float = d.move_acceleration / d.drag
	_add("dipsa: steers toward the player", "vx(1 s)=%.1f, vx(5 s)=%.1f, faces right=%s, y drift=%.2f" % [v1, vmax, flipped_right, d.global_position.y - (REST_Y - 100.0)],
			"vx(1 s) ~%.1f, top speed ~%.1f (80 px/s^2, drag 1.5), sprite flips right" % [expected1, top],
			absf(v1 - expected1) < 3.0 and vmax > top - 4.0 and vmax < top + 1.0 and flipped_right)
	# Stops thrusting inside 160 px: place the player 100 px away; velocity decays to ~0.
	player.global_position = Vector2(d.global_position.x + 100.0, d.global_position.y)
	await _frames(240)
	_add("dipsa: hovers inside 160 px", "vx=%.2f, should_stop_moving=%s" % [d.velocity.x, d.should_stop_moving], "stops thrusting (drag brings it to rest)",
			d.should_stop_moving and absf(d.velocity.x) < 1.0)
	player.is_kinematic = false


func _test_dipsa_shooting() -> void:
	await _reset(0.0)
	var hp0: int = gs.current_hp
	var d := _spawn(DIPSA_PATH, Vector2(100.0, REST_Y - 20.0))
	var first_seen: Dictionary = {}
	var spawn_frames: Array = []
	var first_bullet_vel := Vector2.ZERO
	var first_bullet_pos := Vector2.ZERO
	var hit_frame := -1
	var frame := 0
	while frame < 400:
		await _frames(1)
		frame += 1
		for b: Node in get_nodes_in_group("projectiles"):
			if not first_seen.has(b.get_instance_id()):
				first_seen[b.get_instance_id()] = frame
				spawn_frames.append(frame)
				if spawn_frames.size() == 1:
					first_bullet_vel = b.velocity
					first_bullet_pos = b.global_position
		if hit_frame == -1 and gs.current_hp < hp0:
			hit_frame = frame
	var dir_expected := (Vector2(0.0, REST_Y) - d.global_position).normalized()
	var spawn_expected := d.global_position + Vector2(-0.24 * 16.0, 0.8 * 16.0)
	var cadence_ok: bool = spawn_frames.size() >= 2 and absi(spawn_frames[0] - 180) <= 3 and absi((spawn_frames[1] as int) - (spawn_frames[0] as int) - 180) <= 3
	_add("dipsa: shoots every 3 s once alerted", "bullets at game frames %s (3 s = 180)" % [spawn_frames], "first ~180, then every 180", cadence_ok)
	_add("dipsa: bullet speed / direction / spawn", "|v|=%.1f dir=(%.3f, %.3f), spawn offset=(%.1f, %.1f)" % [first_bullet_vel.length(), first_bullet_vel.normalized().x, first_bullet_vel.normalized().y, first_bullet_pos.x - d.global_position.x, first_bullet_pos.y - d.global_position.y],
			"80 px/s toward the player, spawned at ShootPos (-3.8, +12.8) (+-1 tick of flight)",
			absf(first_bullet_vel.length() - 80.0) < 0.5 and first_bullet_vel.normalized().distance_to(dir_expected) < 0.01 and first_bullet_pos.distance_to(spawn_expected) < 2.0)
	_add("dipsa: bullet hurts the player", "hp %d -> %d at game frame %d" % [hp0, gs.current_hp, hit_frame], "-1 (bullet damage 1) about 1.1 s after the shot",
			hit_frame > 180 and hit_frame < 330 and gs.current_hp <= hp0 - 1)
	d.queue_free()


func _test_bullet_cases() -> void:
	# 1) bullet into the floor dies without damage
	await _reset(200.0)
	var hp0: int = gs.current_hp
	var b := _spawn(BULLET_PATH, Vector2(0.0, -30.0)) as Node2D
	b.velocity = Vector2(0.0, 80.0)
	await _frames(60)
	_add("bullet: dies on Ground (max_bounce 0), no damage", "is_dead=%s bounce=%d hp %d -> %d" % [b.is_dead, b.bounce_counter, hp0, gs.current_hp],
			"dead after the first ground contact", b.is_dead and b.bounce_counter == 1 and gs.current_hp == hp0)
	# 2) bullet passes through the player while i-frames are on
	await _reset(0.0)
	player.in_i_frame = true
	var b2 := _spawn(BULLET_PATH, Vector2(-40.0, REST_Y)) as Node2D
	b2.velocity = Vector2(80.0, 0.0)
	await _frames(120)
	var passed: bool = b2.global_position.x > 20.0 and not b2.is_dead
	var hp_i: int = gs.current_hp
	player.in_i_frame = false
	_add("bullet: ignores the player during i-frames", "x=%.1f dead=%s hp=%d" % [b2.global_position.x, b2.is_dead, hp_i], "passes through, no damage", passed and hp_i == gs.max_hp)
	b2.queue_free()
	# 3) status effect + dies on hit + knockback direction
	await _reset(0.0)
	player.in_i_frame = false
	var b3 := _spawn(BULLET_PATH, Vector2(-40.0, REST_Y), {"inflict_status": 1}) as Node2D # PARALYZED
	b3.velocity = Vector2(80.0, 0.0)
	await _frames(40)
	_add("bullet: damage 1 + status effect, then dies", "hp %d, paralyzed=%s, bullet dead=%s" % [gs.current_hp, player.is_paralyzed, b3.is_dead], "hp 4, paralyzed, bullet consumed",
			gs.current_hp == gs.max_hp - 1 and player.is_paralyzed and b3.is_dead)
	# 4) lifetime
	await _reset(0.0)
	var b4 := _spawn(BULLET_PATH, Vector2(-300.0, -200.0), {"lifetime": 0.5}) as Node2D
	b4.velocity = Vector2.ZERO
	await _frames(20)
	var alive_mid: bool = is_instance_valid(b4) and not b4.is_queued_for_deletion()
	await _frames(20)
	_add("bullet: hard lifetime", "alive at 0.33 s=%s, freed after 0.67 s (lifetime 0.5)=%s" % [alive_mid, not is_instance_valid(b4) or b4.is_queued_for_deletion()], "freed when lifetime elapses",
			alive_mid and (not is_instance_valid(b4) or b4.is_queued_for_deletion()))


func _test_dipsa_slash_death() -> void:
	# Dipsa hit by a real slash: it is within 160 px so it is alerted, but a thrust-free hover keeps it put.
	await _kill_by_slash_and_check(DIPSA_PATH, Vector2(24.0, REST_Y), "dipsa", 8, 5, 1, 2)


# --- Crabber ---

func _test_crabber_alert_walk() -> void:
	await _reset(0.0)
	var cr := _spawn(CRABBER_PATH, Vector2(-150.0, -5.2))
	await _frames(60)
	var idle_ok: bool = not cr.alerted and absf(cr.velocity.x) < 0.5
	player.global_position = Vector2(-60.0, REST_Y) # 90 px away: inside 96 + player half width
	await _frames(3)
	var alerted: bool = cr.alerted
	_add("crabber: idle until the player is within 96 px", "idle at 150 px=%s, alerted at 90 px=%s" % [idle_ok, alerted], "idle, alerted", idle_ok and alerted)
	_add("crabber: stats", "hp %d, type %d, drop %d, detect %.0f, attack radius %.0f" % [cr.max_hp, cr.enemy_type, cr.drop_amount, cr.detection_radius, cr.attack_radius],
			"12, 3, 4, 96, 48", cr.max_hp == 12 and cr.enemy_type == 3 and cr.drop_amount == 4 and cr.detection_radius == 96.0 and cr.attack_radius == 48.0)
	# Walking speed (player far away so the crab keeps walking): fresh crab, alerted by hand.
	await _reset(0.0)
	player.is_kinematic = true
	player.global_position = Vector2(460.0, REST_Y - 200.0)
	var c2 := _spawn(CRABBER_PATH, Vector2(-440.0, -5.2), {"alerted": true})
	await _frames(240)
	var x0: float = c2.global_position.x
	await _frames(60)
	var speed: float = c2.global_position.x - x0
	var expected: float = (c2.move_acceleration - c2.friction * UNITY_G * c2.gravity_scale)
	expected = expected / c2.drag * (1.0 - exp(-4.5 * c2.drag)) # about t = 4.5 s (mid measurement window)
	var faces_right: bool = c2.visual.scale.x < 0.0
	_add("crabber: walking speed toward the player", "%.1f px/s, faces right=%s" % [speed, faces_right], "~65 (128 px/s^2 force - friction 62.7, drag 1; plan target ~64)",
			speed > 60.0 and speed < 68.0 and faces_right)
	player.is_kinematic = false


func _test_crabber_attack() -> void:
	await _reset(0.0)
	var hp0: int = gs.current_hp
	var cr := _spawn(CRABBER_PATH, Vector2(-40.0, -5.2))
	var alert_frame := -1
	var attack_start := -1
	var attack_end := -1
	var max_dv := 0.0
	var prev_vx := 0.0
	var hurt_frame := -1
	var dv_frames: Array = []
	var frame := 0
	while frame < 420:
		await _frames(1)
		frame += 1
		if alert_frame == -1 and cr.alerted:
			alert_frame = frame
		if attack_start == -1 and cr.in_attack:
			attack_start = frame
		if attack_start != -1 and attack_end == -1 and not cr.in_attack:
			attack_end = frame
		if attack_start != -1 and attack_end == -1:
			var dv: float = cr.velocity.x - prev_vx
			if dv > 40.0:
				dv_frames.append([frame - attack_start, dv])
		prev_vx = cr.velocity.x
		if hurt_frame == -1 and gs.current_hp < hp0:
			hurt_frame = frame
	var start_delta: int = attack_start - alert_frame
	var dur: int = attack_end - attack_start
	_add("crabber: attacks every 3 s inside 48 px", "alerted at frame %d, attack began %d frames later (%.2f s), lasted %d frames (%.2f s)" % [alert_frame, start_delta, start_delta / FPS, dur, dur / FPS],
			"~180 frames after alert; clip 1.35 s (BeginAttack 0 .. EndAttack 1.333)",
			absi(start_delta - 180) <= 3 and absi(dur - 80) <= 3)
	var dash_ok: bool = dv_frames.size() == 2 and absi((dv_frames[0][0] as int) - 20) <= 2 and absi((dv_frames[1][0] as int) - 60) <= 2
	var dv_txt := ""
	for d: Array in dv_frames:
		dv_txt += "[+%d fr: dv=%.1f] " % [d[0], d[1]]
	_add("crabber: dash_forward x2 (+96 px/s toward the player)", dv_txt, "at 0.333 s (20 fr) and 1.0 s (60 fr), dv ~ +96 (one fixed step of AddForce 300)",
			dash_ok and absf((dv_frames[0][1] as float) - 96.0) < 8.0 and absf((dv_frames[1][1] as float) - 96.0) < 8.0)
	_add("crabber: attack hurts the player", "hp %d -> %d at game frame %d (%d frames after the attack began)" % [hp0, gs.current_hp, hurt_frame, hurt_frame - attack_start],
			"-1 from the dash contact", hurt_frame > attack_start and gs.current_hp == hp0 - 1)
	var idle_again: bool = cr.anim.current_animation == "idle"
	_add("crabber: back to idle after the attack", "anim=%s in_attack=%s" % [cr.anim.current_animation, cr.in_attack], "idle, not in attack", idle_again and not cr.in_attack)


func _test_crabber_slash_death() -> void:
	# alerted + inside 48 px: it does not walk, so the 24 px slash target stays in reach.
	await _kill_by_slash_and_check(CRABBER_PATH, Vector2(24.0, -5.2), "crabber", 12, 4, 3, 20)


# --- Loot ---

func _test_loot() -> void:
	await _reset(0.0)
	var c0: int = gs.copper_shard
	var l := _spawn(LOOT_PATH, Vector2(-80.0, -20.0)) as Node2D
	await _frames(120)
	var landed: bool = l.is_on_floor() and l.global_position.y > -5.0 and l.global_position.y < 2.0
	var untouched: bool = gs.copper_shard == c0
	var scale_x: float = l.sprite.scale.x
	player.global_position = Vector2(l.global_position.x, REST_Y)
	await _frames(4)
	_add("loot: falls, rests on the floor, spins, is picked up", "landed=%s (y=%.1f), untouched before=%s, spin scale.x=%.3f, copper %d -> %d, picked_up=%s, sprite hidden=%s" % [landed, l.global_position.y, untouched, scale_x, c0, gs.copper_shard, l.picked_up, not l.sprite.visible],
			"+1 copper shard exactly once", landed and untouched and gs.copper_shard == c0 + 1 and l.picked_up and not l.sprite.visible)
	await _frames(70)
	_add("loot: freed 1 s after pickup", "valid=%s" % [is_instance_valid(l) and not l.is_queued_for_deletion()], "freed", not is_instance_valid(l) or l.is_queued_for_deletion())
	# auto-free
	var l2 := _spawn(LOOT_PATH, Vector2(300.0, -20.0), {"destroy_time": 0.5}) as Node2D
	await _frames(40)
	var gone: bool = not is_instance_valid(l2) or l2.is_queued_for_deletion()
	_add("loot: auto-free after destroy_time", "freed after 0.67 s with destroy_time 0.5 = %s" % gone, "freed (default 20 s)", gone)
	var l3 := (load(LOOT_PATH) as PackedScene).instantiate()
	_add("loot: defaults", "value %d, destroy %.0f s, gravity %.0f, drag %.0f, anim speed %.0f" % [l3.value, l3.destroy_time, l3.gravity_scale, l3.drag, l3.anim_speed],
			"1, 20, 2, 1, 5", l3.value == 1 and l3.destroy_time == 20.0 and l3.gravity_scale == 2.0 and l3.drag == 1.0 and l3.anim_speed == 5.0)
	l3.free()


# --- Rooms ---

func _test_room_smoke(n: int) -> void:
	await _reset(0.0)
	_clear_world()
	tilemap.collision_enabled = false
	player.is_kinematic = true
	player.global_position = Vector2(0.0, -5000.0) # far above: nothing is alerted
	await _frames(2)
	var room := (load("res://scenes/rooms/dirt_cave_%d.tscn" % n) as PackedScene).instantiate()
	root.add_child(room)
	var start: Dictionary = {}
	var list: Array = []
	for c in room.get_children():
		if c.is_in_group("enemy_spawns"):
			start[c.name] = (c as Node2D).global_position
			list.append(c)
	await _frames(30)
	var after_settle: Dictionary = {}
	for c: Node2D in list:
		after_settle[c.name] = c.global_position
	await _frames(600)
	var rect: Rect2i = (room.get_node("Tilemap") as TileMapLayer).get_used_rect()
	var bounds := Rect2(Vector2(rect.position) * 16.0, Vector2(rect.size) * 16.0)
	var txt := ""
	var ok := true
	for c: Node2D in list:
		var kind: String = String(c.get_meta("enemy_type"))
		var p: Vector2 = c.global_position
		var inside: bool = bounds.has_point(p)
		var drop: float = p.y - (start[c.name] as Vector2).y
		var good: bool = inside and drop < 40.0 and c.is_in_group("enemies")
		if kind == "Crawling":
			good = good and c.is_on_floor()
		elif kind == "Dipsa":
			good = good and p.distance_to(start[c.name] as Vector2) < 1.0 and not c.alerted
		elif kind == "Crabber":
			good = good and c.is_on_floor() and not c.alerted
		if not good:
			ok = false
		txt += "%s %s:(%.0f,%.0f)->(%.0f,%.0f)%s " % [kind, c.name, (start[c.name] as Vector2).x, (start[c.name] as Vector2).y, p.x, p.y, "" if good else "!!"]
	_add("DirtCave%d: %d enemies settle and patrol sanely for 10 s" % [n, list.size()], txt, "inside the room, resting on floor / hovering, none alerted, none fell > 40 px", ok and list.size() > 0)
	room.queue_free()
	tilemap.collision_enabled = true
	await _frames(2)
	player.is_kinematic = false


func _print_table() -> void:
	print("")
	print("=== P5 enemy test (60 Hz physics) ===")
	for r: Array in rows:
		print("[%s] %-52s measured: %s | expected: %s%s" % [r[3], r[0], r[1], r[2], ("  (" + (r[4] as String) + ")") if (r[4] as String) != "" else ""])
	print("test_enemies: ", "FAILED (%d)" % fails if fails > 0 else "ALL PASS")
