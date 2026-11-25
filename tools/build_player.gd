extends SceneTree
## Builds res://scenes/player/player.tscn (nodes + AnimationPlayer clips).
## Run: godot --headless --path . -s tools/build_player.gd
## Clip timings are read from Assets/Player/Animation/*.anim (m_PPtrCurves).

const OUT_PATH := "res://scenes/player/player.tscn"
const SPRITE_DIR := "res://assets/player/"
const SPRITE_PATH := "Visual/Sprite2D"
## Unity: m_StopTime of the 1-frame clips (one 60 Hz sample).
const ONE_FRAME_LENGTH := 0.016666668

## name -> [sheet, hframes, [frame indices], [times], length]
const CLIPS := {
	"idle": ["tenroh_idle.png", 3, [0, 1, 2, 0], [0.0, 0.16666667, 0.33333334, 0.5], 0.51666665],
	"run": ["tenroh_run.png", 2, [0, 1, 0], [0.0, 0.16666667, 0.33333334], 0.35000002],
	"jump": ["tenroh_jump.png", 1, [0], [0.0], ONE_FRAME_LENGTH],
	"fall": ["tenroh_fall.png", 1, [0], [0.0], ONE_FRAME_LENGTH],
	"dash": ["tenroh_dash.png", 1, [0], [0.0], ONE_FRAME_LENGTH],
	"ledge_grab": ["tenroh_grabLedge.png", 1, [0], [0.0], ONE_FRAME_LENGTH],
	"hurt": ["tenroh_hurt.png", 1, [0], [0.0], ONE_FRAME_LENGTH],
}


func _initialize() -> void:
	# Autoload globals (GameState) only exist after the first frame in -s scripts.
	await process_frame
	var player_script: GDScript = load("res://scenes/player/player.gd")
	var sfx_script: GDScript = load("res://scenes/player/player_sfx.gd")
	if player_script == null or sfx_script == null:
		push_error("build_player: scripts failed to load")
		quit(1)
		return

	var player := CharacterBody2D.new()
	player.name = "Player"
	player.set_script(player_script)
	player.collision_layer = 2
	player.collision_mask = 1
	player.add_to_group("player", true)
	player.set("stats", load("res://resources/player_stats_default.tres"))

	var body := CollisionShape2D.new()
	body.name = "Body"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12.8, 23.0)
	body.shape = rect
	body.position = Vector2(0, 2.7)
	_add(player, player, body)

	var visual := Node2D.new()
	visual.name = "Visual"
	_add(player, player, visual)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load(SPRITE_DIR + "tenroh_idle.png")
	sprite.hframes = 3
	sprite.scale = Vector2(0.25, 0.25)
	_add(player, visual, sprite)

	for entry: Array in [
		["DashAttackPos", Vector2(16, 4.8)],
		["PogoAttackPos", Vector2(4.3, 7.5)],
		["LedgeGreen", Vector2(8, 0)],
		["LedgeRed", Vector2(8, -8)],
	]:
		var m := Marker2D.new()
		m.name = entry[0] as String
		m.position = entry[1] as Vector2
		_add(player, visual, m)

	_add(player, visual, _make_dust())

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	_add(player, player, ap)
	var lib := AnimationLibrary.new()
	for clip_name: String in CLIPS:
		lib.add_animation(clip_name, _make_clip(CLIPS[clip_name] as Array))
	ap.add_animation_library("", lib)

	var sfx := Node.new()
	sfx.name = "Sfx"
	sfx.set_script(sfx_script)
	_add(player, player, sfx)
	sfx.set("player", player)

	var packed := PackedScene.new()
	var err := packed.pack(player)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	print("build_player: saved %s (err %d)" % [OUT_PATH, err])
	player.free()
	quit(0 if err == OK else 1)


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	if child != owner_node:
		parent.add_child(child)
		child.owner = owner_node


func _make_dust() -> CPUParticles2D:
	# Unity DustPE: lifetime 0.5 s, start size 0.2 u (3.2 px). Simple brown puff.
	var p := CPUParticles2D.new()
	p.name = "DustPE"
	p.position = Vector2(1.7, 13.4)
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 0.5
	p.explosiveness = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 35.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.2
	p.color = Color(0.55, 0.42, 0.28, 0.9)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	return p


func _make_clip(d: Array) -> Animation:
	var a := Animation.new()
	var frames: Array = d[2]
	var times: Array = d[3]
	a.length = d[4] as float
	a.loop_mode = Animation.LOOP_LINEAR

	var t_tex := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_tex, NodePath(SPRITE_PATH + ":texture"))
	a.value_track_set_update_mode(t_tex, Animation.UPDATE_DISCRETE)
	a.track_insert_key(t_tex, 0.0, load(SPRITE_DIR + (d[0] as String)))

	var t_h := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_h, NodePath(SPRITE_PATH + ":hframes"))
	a.value_track_set_update_mode(t_h, Animation.UPDATE_DISCRETE)
	a.track_insert_key(t_h, 0.0, d[1] as int)

	var t_f := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_f, NodePath(SPRITE_PATH + ":frame"))
	a.value_track_set_update_mode(t_f, Animation.UPDATE_DISCRETE)
	a.track_set_interpolation_type(t_f, Animation.INTERPOLATION_NEAREST)
	for i in frames.size():
		a.track_insert_key(t_f, times[i] as float, frames[i] as int)
	return a
