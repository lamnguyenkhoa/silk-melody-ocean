extends SceneTree
## One-shot helper used in P0 to write project.godot settings via the engine API
## (guarantees correct InputEvent serialization). Run:
##   godot --headless --path . -s tools/setup_project_settings.gd

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e

func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = -1
	return e

func _set_action(name: String, events: Array, deadzone: float = 0.5) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": deadzone, "events": events})

func _init() -> void:
	ProjectSettings.set_setting("display/window/size/viewport_width", 384)
	ProjectSettings.set_setting("display/window/size/viewport_height", 216)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1536)
	ProjectSettings.set_setting("display/window/size/window_height_override", 864)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")
	ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
	ProjectSettings.set_setting("physics/3d/physics_engine", null)

	var layers := ["Ground", "Player", "Enemy", "PlayerAttack", "EnemyAttack", "Loot", "DeadEnemy", "PlayerTrigger"]
	for i in layers.size():
		ProjectSettings.set_setting("layer_names/2d_physics/layer_%d" % (i + 1), layers[i])

	_set_action("move_left", [_key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _btn(JOY_BUTTON_DPAD_LEFT)], 0.2)
	_set_action("move_right", [_key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _btn(JOY_BUTTON_DPAD_RIGHT)], 0.2)
	_set_action("move_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0), _btn(JOY_BUTTON_DPAD_UP)], 0.2)
	_set_action("move_down", [_key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0), _btn(JOY_BUTTON_DPAD_DOWN)], 0.2)
	_set_action("jump", [_key(KEY_X), _btn(JOY_BUTTON_A)])
	_set_action("attack", [_key(KEY_C), _btn(JOY_BUTTON_X)])
	_set_action("dash", [_key(KEY_Z), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_set_action("silk_skill", [_key(KEY_Q), _btn(JOY_BUTTON_B)])
	_set_action("parry", [_key(KEY_F), _btn(JOY_BUTTON_Y)])
	_set_action("pause", [_key(KEY_ESCAPE), _btn(JOY_BUTTON_BACK)])

	ProjectSettings.set_setting("autoload/GameState", "*res://autoload/game_state.gd")
	ProjectSettings.set_setting("autoload/Hitstop", "*res://autoload/hitstop.gd")
	ProjectSettings.set_setting("autoload/RoomLoader", "*res://autoload/room_loader.gd")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/world/world.tscn")

	var err := ProjectSettings.save()
	print("ProjectSettings.save() -> ", err)
	quit(0 if err == OK else 1)
