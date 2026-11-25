class_name GameCamera
extends Camera2D
## Camera follow + room limits + shake (plan 7.4; CM vcam1 prefab, CinemachineShake.cs).
## The node itself is placed on the target every physics tick; Camera2D's built-in position
## smoothing and drag margins then do the Cinemachine-style damping around it.

## Pixels per tile (room limits come from tile cells).
const TILE_SIZE: int = 16
## Unity: lens OrthographicSize 6 -> 12 u = 192 px visible height; viewport is 216 px tall.
const CAMERA_ZOOM: float = 216.0 / 192.0
## Unity: CinemachineFramingTransposer X/Y damping 1 -> approx. Godot smoothing speed (plan 7.4).
const FOLLOW_SMOOTHING_SPEED: float = 5.0
## Unity: m_DeadZoneWidth/Height 0.2 (central 20 % of the screen, i.e. +-10 % from centre).
## Godot drag margins are measured from the screen CENTRE as a fraction of half the screen
## (0 = always follow, 1 = only at the edge), so +-10 % of the screen = margin 0.2.
const DEAD_ZONE: float = 0.2
## Shake amplitude in px per unit of "intensity" (plan 7.4: intensity 5 ~ 6 px).
const SHAKE_PX_PER_INTENSITY: float = 1.2

@export var target: Node2D

var _shake_amplitude: float = 0.0
var _shake_duration: float = 0.0
var _shake_unscaled: bool = false
var _shake_start: float = 0.0
var _shake_active: bool = false
var _scaled_clock: float = 0.0

func _ready() -> void:
	# Keep ticking during hit-stop (Engine.time_scale 0) so unscaled shakes play.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	zoom = Vector2.ONE * CAMERA_ZOOM
	position_smoothing_enabled = true
	position_smoothing_speed = FOLLOW_SMOOTHING_SPEED
	var margin: float = DEAD_ZONE
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = margin
	drag_right_margin = margin
	drag_top_margin = margin
	drag_bottom_margin = margin
	limit_smoothed = true

func _physics_process(_delta: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position

func _process(delta: float) -> void:
	_scaled_clock += delta
	if not _shake_active:
		return
	var elapsed: float = _now(_shake_unscaled) - _shake_start
	if elapsed >= _shake_duration:
		_shake_active = false
		offset = Vector2.ZERO
		return
	var amp: float = _shake_amplitude * (1.0 - elapsed / _shake_duration)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp

func _now(unscaled: bool) -> float:
	return Time.get_ticks_msec() / 1000.0 if unscaled else _scaled_clock

## CinemachineShake.ShakeCamera(intensity, time): amplitude decays linearly to 0 over [param time].
## [param unscaled] ticks with real time so the shake still plays during hit-stop.
func shake(intensity: float, time: float, unscaled: bool = false) -> void:
	if time <= 0.0:
		return
	_shake_amplitude = intensity * SHAKE_PX_PER_INTENSITY
	_shake_duration = time
	_shake_unscaled = unscaled
	_shake_start = _now(unscaled)
	_shake_active = true

## Sets the scroll limits from the room's collision TileMapLayer ("Tilemap") used rect.
func set_room_limits(room: Node) -> void:
	var tm := room.get_node_or_null("Tilemap") as TileMapLayer
	if tm == null:
		push_warning("GameCamera.set_room_limits: room '%s' has no Tilemap" % room.name)
		return
	var rect: Rect2i = tm.get_used_rect()
	var origin: Vector2 = tm.global_position
	limit_left = int(origin.x) + rect.position.x * TILE_SIZE
	limit_top = int(origin.y) + rect.position.y * TILE_SIZE
	limit_right = int(origin.x) + rect.end.x * TILE_SIZE
	limit_bottom = int(origin.y) + rect.end.y * TILE_SIZE

## Jump straight onto the target (room entry / teleport) without smoothing.
func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position
	reset_smoothing()
	force_update_scroll()
