class_name DebugOverlay
extends CanvasLayer
## Playtest overlay (F3 toggles; on by default in debug builds). Plan P2 deliverable 4.

const TILE_SIZE: float = 16.0
const FONT_SIZE: int = 8

var _label: Label
var _player: Player

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(4, 4)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)
	visible = OS.is_debug_build()

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible

func _process(_delta: float) -> void:
	if not visible:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			_label.text = "(no player)"
			return
	var v: Vector2 = _player.velocity
	_label.text = "\n".join([
		"vel px/s: (%.1f, %.1f)" % [v.x, v.y],
		"vel tiles/s: (%.2f, %.2f)" % [v.x / TILE_SIZE, v.y / TILE_SIZE],
		"on_floor: %s  grounded: %s" % [_player.is_on_floor(), _player.is_grounded],
		"anim state: %s (%s)" % [_player.get_state_name(), _player.anim.current_animation],
		"dash_count: %d  jump_count: %d" % [_player.dash_count, _player.jump_count],
		"coyote timer: %.3f" % _player.coyote_air_timer,
		"ledge_grabbing: %s" % _player.is_ledge_grabbing,
		"pos: (%.1f, %.1f)  fps: %d" % [_player.global_position.x, _player.global_position.y, Engine.get_frames_per_second()],
		"[F3] overlay  [F9] camera shake test",
	])
