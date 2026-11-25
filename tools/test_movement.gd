extends SceneTree
## Automated movement test (plan P2). Builds a flat test room with the real tileset, instances the
## real player scene, simulates inputs and measures run / jump / dash / fall / coyote / ledge grab.
## Run: godot --headless --path . -s tools/test_movement.gd
## Physics runs at 60 Hz here (Unity: 50 Hz), so small differences are expected.

const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const TILE := 16.0
const SOLID_ATLAS := Vector2i(3, 3)
## Test-room layout (cells). Main floor top edge is at y = 0 px.
const FLOOR_X := [-30, 40]      # inclusive cell range
const FLOOR_Y := [0, 2]
const WALL_X := [10, 13]        # wall (for the ledge test), top edge at y = -64 px
const WALL_Y := [-4, -1]
const LEDGE_PLAT_X := [-80, -60] # separate platform for the coyote test (right edge x = -59*16)
const REST_Y := -14.3           # player origin when standing on the floor
const WALL_PLAYER_X := 152.0    # origin x so the green probe touches the wall but the body doesn't

var player # untyped: Player class_name would be compiled before autoloads exist
var rows: Array = []
var fails: int = 0
var tilemap: TileMapLayer


func _initialize() -> void:
	# Autoloads (GameState) are only in the tree after the first frame in -s scripts.
	await process_frame
	_build_room()
	var ps: PackedScene = load(PLAYER_PATH)
	player = ps.instantiate()
	root.add_child(player)
	player.global_position = Vector2(0, REST_Y)
	await _frames(20)

	await _test_run()
	await _test_jump_full()
	await _test_jump_tap()
	await _test_dash()
	await _test_terminal()
	await _test_coyote()
	await _test_ledge()

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
	for x in range(WALL_X[0] as int, (WALL_X[1] as int) + 1):
		for y in range(WALL_Y[0] as int, (WALL_Y[1] as int) + 1):
			tilemap.set_cell(Vector2i(x, y), 0, SOLID_ATLAS)
	for x in range(LEDGE_PLAT_X[0] as int, (LEDGE_PLAT_X[1] as int) + 1):
		for y in range(FLOOR_Y[0] as int, (FLOOR_Y[1] as int) + 1):
			tilemap.set_cell(Vector2i(x, y), 0, SOLID_ATLAS)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _act(action: StringName, pressed: bool, strength: float = 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = strength if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events() # dispatch now so the next physics tick sees it


func _release_all() -> void:
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"dash"]:
		if Input.is_action_pressed(a):
			_act(a, false)


## Puts the player back on the floor at x, clears all transient state, lets it settle.
func _reset(x: float, y: float = REST_Y) -> void:
	_release_all()
	player.cancel_dash()
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	player.is_dashing = false
	player.is_jumping = false
	player.is_ledge_grabbing = false
	player.gravity_on = true
	player.is_facing_left = false
	player.coyote_air_timer = 0.0
	player.air_time = 0.0
	await _frames(15)


func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1


# --- tests ---

func _test_run() -> void:
	await _reset(0.0)
	_act(&"move_right", true)
	await _frames(10) # accelerate / settle
	var x0: float = player.global_position.x
	var n := 60
	await _frames(n)
	var dx: float = player.global_position.x - x0
	var v: float = dx / (n / 60.0)
	_release_all()
	# Commanded speed is 112 px/s; Unity's linear drag (2) is applied after it every step:
	# effective = 112 / (1 + 2 * dt) = 108.4 px/s.
	var gs: Node = root.get_node("GameState")
	var drag_expected: float = (gs.get("move_speed") as float) / (1.0 + player.stats.linear_drag / 60.0)
	_add("run speed (flat, 1 s)", "%.1f px/s" % v, "112 cmd / %.1f after drag" % drag_expected,
			absf(v - drag_expected) < 1.0, "%.2f tiles/s" % (v / TILE))


func _test_jump_full() -> void:
	await _reset(0.0)
	var y0: float = player.global_position.y
	var top: float = y0
	_act(&"jump", true)
	var guard := 0
	while guard < 120:
		await physics_frame
		guard += 1
		top = minf(top, player.global_position.y)
		if guard > 3 and player.velocity.y > 0.0:
			break
	_release_all()
	var h: float = y0 - top
	# Plan estimate was ~5 tiles (75-90 px), but the Unity formulas themselves (hold 0.3 s at 192 px/s,
	# gravity then drag each step) give 63.8 px at 50 Hz / 68.5 px at 60 Hz (hand simulation), so the
	# check allows 60-92 px and the discrepancy with the plan estimate is reported, not tuned away.
	_add("full-hold jump apex", "%.1f px (%.2f tiles)" % [h, h / TILE], "plan ~5 tiles (75-90); formula 64-69 px",
			h >= 60.0 and h <= 92.0, "below plan estimate; see log")


func _test_jump_tap() -> void:
	await _reset(0.0)
	var y0: float = player.global_position.y
	var top: float = y0
	_act(&"jump", true)
	await physics_frame
	_act(&"jump", false)
	var guard := 0
	while guard < 120:
		await physics_frame
		guard += 1
		top = minf(top, player.global_position.y)
		if guard > 3 and player.velocity.y > 0.0:
			break
	var h: float = y0 - top
	_add("tap jump apex (release after 1 frame)", "%.1f px (%.2f tiles)" % [h, h / TILE], "much lower than full hold",
			h < 30.0 and h > 0.0)


func _test_dash() -> void:
	await _reset(0.0)
	var x0: float = player.global_position.x
	_act(&"dash", true)
	await physics_frame
	_act(&"dash", false)
	var frames := 1
	while player.is_dashing and frames < 60:
		await physics_frame
		frames += 1
	await _frames(2)
	var dist: float = player.global_position.x - x0
	var dash_s := frames / 60.0
	# Analytic: integral of 320 * exp(-2 t) over dash_time = 160 * (1 - e^-0.5) = 62.9 px
	_add("dash distance (standstill, grounded)", "%.1f px (%.2f tiles), %.3f s" % [dist, dist / TILE, dash_s],
			"~4 tiles (60-70 px), 0.25 s", dist >= 58.0 and dist <= 72.0 and absf(dash_s - 0.25) < 0.05)
	await _frames(30)


func _test_terminal() -> void:
	await _reset(0.0, -3000.0)
	var vmax := 0.0
	for i in 400:
		await physics_frame
		vmax = maxf(vmax, player.velocity.y)
		if player.is_grounded:
			break
	# Analytic limit: gravity / drag = 784.8 / 2 = 392.4 px/s.
	_add("terminal fall speed", "%.1f px/s (%.1f tiles/s)" % [vmax, vmax / TILE], "~400 px/s (g/drag = 392.4)",
			vmax >= 380.0 and vmax <= 410.0)


func _walk_off_and_jump(wait_frames: int) -> bool:
	# Start on the separate platform, walk right off its edge, press jump `wait_frames`
	# physics frames after is_grounded first turns false. Returns whether the jump started.
	var edge_x := (LEDGE_PLAT_X[1] as float + 1.0) * TILE
	await _reset(edge_x - 40.0)
	_act(&"move_right", true)
	var guard := 0
	while player.is_grounded and guard < 300:
		await physics_frame
		guard += 1
	await _frames(wait_frames)
	_act(&"jump", true)
	await physics_frame
	var jumped: bool = player.is_jumping
	_release_all()
	await _frames(5)
	return jumped


func _test_coyote() -> void:
	var near := await _walk_off_and_jump(8)   # coyote timer ~ 9 frames = 0.15 s
	var late := await _walk_off_and_jump(14)  # coyote timer ~ 15 frames = 0.25 s
	_add("coyote: jump 0.15 s after leaving ledge", "jumped=%s" % near, "jumps", near)
	_add("coyote: jump 0.25 s after leaving ledge", "jumped=%s" % late, "does not jump (extra_jump 0)", not late)


func _test_ledge() -> void:
	await _reset(WALL_PLAYER_X)
	var top_px := (WALL_Y[0] as float) * TILE
	_act(&"jump", true)
	var grabbed := false
	var guard := 0
	while guard < 240:
		await physics_frame
		guard += 1
		if player.is_ledge_grabbing:
			grabbed = true
			break
	_release_all() # releasing jump now: is_jumping is false by then, so no hard cut
	var stuck_ok := false
	var y_at: float = player.global_position.y
	if grabbed:
		await _frames(10)
		stuck_ok = player.velocity == Vector2.ZERO and player.is_ledge_grabbing \
				and absf(player.global_position.y - y_at) < 0.01 and not player.gravity_on
	_add("ledge grab (jump beside wall-top)", "grabbed=%s, held still 10 frames=%s, y=%.1f (top %.0f)" \
			% [grabbed, stuck_ok, player.global_position.y, top_px], "grab, vel 0, no gravity", grabbed and stuck_ok)
	# Jump from the ledge.
	var y_grab: float = player.global_position.y
	_act(&"jump", true)
	await physics_frame
	var vy_after: float = player.velocity.y
	var released: bool = not player.is_ledge_grabbing
	var top: float = y_grab
	for i in 40:
		await physics_frame
		top = minf(top, player.global_position.y)
	_release_all()
	var rise: float = y_grab - top
	_add("jump from ledge grab", "vy=%.1f, left ledge=%s, rose %.1f px" % [vy_after, released, rise],
			"vy<0, leaves ledge, rises", vy_after < -100.0 and released and rise > 20.0)


func _print_table() -> void:
	print("")
	print("=== P2 movement test (60 Hz physics) ===")
	for r: Array in rows:
		print("[%s] %-42s measured: %-52s expected: %s%s" % [r[3], r[0], r[1], r[2], ("  (" + (r[4] as String) + ")") if (r[4] as String) != "" else ""])
	print("test_movement: ", "FAILED (%d)" % fails if fails > 0 else "ALL PASS")
