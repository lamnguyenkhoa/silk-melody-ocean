class_name HurtVignette
extends CanvasLayer
## Port of PPVolumeController (plan 7.6): on damage the vignette intensity jumps to 0.6 and
## lerps back to the base value over 2 s. Time is scaled (Unity: Time.deltaTime).

## Unity: Global Volume Profile Vignette intensity.
@export var base_intensity: float = 0.3
## Unity: PPVolumeController.HurtVignette start value.
@export var hurt_intensity: float = 0.6
## Unity: PPVolumeController.HurtVignette duration, seconds.
@export var hurt_duration: float = 2.0

var intensity: float = 0.0
var _timer: float = 0.0
var _active: bool = false
var _material: ShaderMaterial

func _ready() -> void:
	add_to_group("hurt_vignette")
	intensity = base_intensity
	var rect := ColorRect.new()
	rect.name = "VignetteRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load("res://scenes/vfx/vignette.gdshader") as Shader
	rect.material = _material
	add_child(rect)
	_apply()

## DamagedPPEffect(): restarts the pulse.
func pulse() -> void:
	intensity = hurt_intensity
	_timer = 0.0
	_active = true
	_apply()

func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	var t: float = clampf(_timer / hurt_duration, 0.0, 1.0)
	intensity = lerpf(hurt_intensity, base_intensity, t)
	if t >= 1.0:
		_active = false
	_apply()

func _apply() -> void:
	_material.set_shader_parameter("intensity", intensity)
