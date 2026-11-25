class_name World
extends Node2D
## Persistent world root (plan 7.1). P2: loads DirtCave0 directly; RoomLoader takes over in P6.

## P2 only: room loaded straight into RoomContainer.
const P2_START_ROOM: String = "res://scenes/rooms/dirt_cave_0.tscn"
## Debug camera-shake test (F9): Unity damage shake uses intensity 5 for 0.3 s.
const DEBUG_SHAKE_INTENSITY: float = 5.0
const DEBUG_SHAKE_TIME: float = 0.3

@onready var room_container: Node2D = $RoomContainer
@onready var player: Player = $Player
@onready var camera: GameCamera = $GameCamera

var current_room: Node

func _ready() -> void:
	camera.target = player
	_load_room_direct(P2_START_ROOM)

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

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F9:
		camera.shake(DEBUG_SHAKE_INTENSITY, DEBUG_SHAKE_TIME, true)
