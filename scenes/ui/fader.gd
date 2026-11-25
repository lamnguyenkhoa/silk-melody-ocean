class_name Fader
extends CanvasLayer
## Screen fade for room transitions (Unity: LevelLoader Crossfade animator, CrossfadeStart /
## CrossfadeEnd.anim = linear alpha 0 -> 1 and 1 -> 0 over 1 s on a full-screen black panel).
## Tweens run on scaled time like the Unity animator (hit-stop pauses them).

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	_rect = ColorRect.new()
	_rect.name = "FadeRect"
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

## Current black alpha (0 = clear, 1 = black).
func alpha() -> float:
	return _rect.color.a

## Linear fade to black over [param duration] (does not block; the caller waits).
func fade_out(duration: float) -> void:
	_fade_to(1.0, duration)

## Linear fade back to clear over [param duration].
func fade_in(duration: float) -> void:
	_fade_to(0.0, duration)

func _fade_to(target: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration <= 0.0:
		_rect.color.a = target
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target, duration)
