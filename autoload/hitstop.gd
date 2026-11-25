extends Node
## Hit-stop / time-scale autoload (plan §0.9). Unity equivalent: WaitForSecondsRealtime.
## Overlapping calls are safe: only the most recent call restores time_scale to 1.0.

var _generation: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Freeze the game (time_scale 0) for [param real_seconds] of real time.
func freeze(real_seconds: float) -> void:
	await slow(0.0, real_seconds)

## Set Engine.time_scale to [param time_scale] for [param real_seconds] of real time.
func slow(time_scale: float, real_seconds: float) -> void:
	_generation += 1
	var my_gen: int = _generation
	Engine.time_scale = time_scale
	# process_always = true, process_in_physics = false, ignore_time_scale = true
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	if my_gen == _generation:
		Engine.time_scale = 1.0
