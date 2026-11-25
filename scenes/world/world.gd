class_name World
extends Node2D
## Persistent world root (plan 7.1). P2: loads DirtCave0 directly; RoomLoader takes over in P6.

## P2 only: room loaded straight into RoomContainer.
const P2_START_ROOM: String = "res://scenes/rooms/dirt_cave_0.tscn"
## Debug camera-shake test (F9): Unity damage shake uses intensity 5 for 0.3 s.
const DEBUG_SHAKE_INTENSITY: float = 5.0
const DEBUG_SHAKE_TIME: float = 0.3
## P3 debug: F10 deals this much damage from the right (knockback points left), so parry can be tested.
const DEBUG_DAMAGE_AMOUNT: int = 1
const DEBUG_DAMAGE_KNOCKBACK := Vector2(-1.0, 0.0)
## P3 debug dummies: scene, how many, candidate x offsets (px) from the floor under PlayerStart,
## and how many free tiles are needed above the floor.
const DUMMY_SCENE := "res://scenes/enemies/training_dummy.tscn"
const DUMMY_COUNT: int = 2
const DUMMY_X_OFFSETS: Array[float] = [48.0, 96.0, -48.0, 144.0, -96.0, 192.0, -144.0]
const DUMMY_FREE_TILES_ABOVE: int = 2
const FLOOR_SCAN_TILES: int = 80
const TILE_SIZE: float = 16.0
## Spawn the dummy a bit above the floor and let gravity settle it.
const DUMMY_DROP_HEIGHT: float = 24.0
## P3 only: the RoomLoader stub (P6) does not respawn, so the world puts the player back at
## PlayerStart after the death transition.
const P3_RESPAWN_FALLBACK_DELAY: float = 1.0

@onready var room_container: Node2D = $RoomContainer
@onready var player: Player = $Player
@onready var camera: GameCamera = $GameCamera

var current_room: Node

func _ready() -> void:
	camera.target = player
	_load_room_direct(P2_START_ROOM)
	player.died.connect(_on_player_died)
	if OS.is_debug_build():
		_spawn_debug_dummies()

func _load_room_direct(path: String) -> void:
	if current_room != null:
		current_room.queue_free()
	current_room = (load(path) as PackedScene).instantiate()
	room_container.add_child(current_room)
	camera.set_room_limits(current_room)
	var start := current_room.get_node_or_null("PlayerStart") as Node2D
	if start != null:
		player.global_position = start.global_position
		player.velocity = Vector2.ZERO
	camera.snap_to_target()

## TODO(P6): RoomLoader.respawn() replaces this.
func _on_player_died() -> void:
	await get_tree().create_timer(P3_RESPAWN_FALLBACK_DELAY, true, true).timeout
	var start := current_room.get_node_or_null("PlayerStart") as Node2D
	if start != null:
		player.global_position = start.global_position
	player.velocity = Vector2.ZERO
	player.is_kinematic = false
	camera.snap_to_target()

## Debug builds only: training dummies on the floor near the PlayerStart landing spot
## (placed at runtime, not baked into the room scene).
func _spawn_debug_dummies() -> void:
	var start := current_room.get_node_or_null("PlayerStart") as Node2D
	var tilemap := current_room.get_node_or_null("Tilemap") as TileMapLayer
	if start == null or tilemap == null:
		return
	var landing_top: float = _find_floor_top(tilemap, start.global_position.x, start.global_position.y)
	if is_nan(landing_top):
		return
	var packed := load(DUMMY_SCENE) as PackedScene
	var placed: int = 0
	for dx: float in DUMMY_X_OFFSETS:
		if placed >= DUMMY_COUNT:
			break
		var x: float = start.global_position.x + dx
		var top: float = _find_floor_top(tilemap, x, landing_top - TILE_SIZE)
		# Same flat floor as the landing spot, with free tiles above.
		if is_nan(top) or not is_equal_approx(top, landing_top) or not _has_free_space(tilemap, x, top):
			continue
		var dummy := packed.instantiate() as Enemy
		dummy.position = Vector2(x, top - DUMMY_DROP_HEIGHT)
		current_room.add_child(dummy)
		placed += 1

## Top edge (px) of the first solid tile at or below [param from_y] in the column of [param x]; NAN if none.
func _find_floor_top(tilemap: TileMapLayer, x: float, from_y: float) -> float:
	var cx: int = floori(x / TILE_SIZE)
	var cy0: int = floori(from_y / TILE_SIZE)
	for cy in range(cy0, cy0 + FLOOR_SCAN_TILES):
		if tilemap.get_cell_source_id(Vector2i(cx, cy)) != -1:
			return cy * TILE_SIZE
	return NAN

func _has_free_space(tilemap: TileMapLayer, x: float, floor_top: float) -> bool:
	var cx: int = floori(x / TILE_SIZE)
	var cy: int = floori(floor_top / TILE_SIZE)
	for i in range(1, DUMMY_FREE_TILES_ABOVE + 1):
		if tilemap.get_cell_source_id(Vector2i(cx, cy - i)) != -1:
			return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F9:
			camera.shake(DEBUG_SHAKE_INTENSITY, DEBUG_SHAKE_TIME, true)
		KEY_F10:
			player.damaged(DEBUG_DAMAGE_AMOUNT, DEBUG_DAMAGE_KNOCKBACK)
		KEY_F11:
			GameState.lifeblood_hp += 1
			GameState.stats_changed.emit()
		KEY_F12:
			GameState.current_silk = GameState.max_silk
			GameState.stats_changed.emit()
