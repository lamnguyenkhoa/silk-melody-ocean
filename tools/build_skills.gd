extends SceneTree
## Builds the P4 scenes:
##   scenes/vfx/silk_bind.tscn, scenes/player/gossamer.tscn, scenes/player/silk_burst.tscn,
##   scenes/ui/hud.tscn
## Run: godot --headless --path . -s tools/build_skills.gd   (order: build_combat, build_skills, build_player)
## Frame/time tables come from Assets/Player/Animation/VFX/{SilkBind,GossamerSilk,SilkBurst}.anim
## (m_PPtrCurves, sprite internalIDs mapped through the .png.meta name tables).

const SPRITE_SCALE := 0.25

## 1/60 s steps used by the Unity clips (sample rate 60).
const T := 1.0 / 60.0

func _initialize() -> void:
	await process_frame # autoloads must exist before the scripts below compile
	var ok := true
	ok = _build_silk_bind() and ok
	ok = _build_gossamer() and ok
	ok = _build_silk_burst() and ok
	ok = _build_hud() and ok
	quit(0 if ok else 1)


func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("build_skills: saved %s (err %d)" % [path, err])
	root.free()
	return err == OK


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node


## Adds an AnimationPlayer with a one-shot "play" clip stepping Sprite2D:frame.
func _add_frame_clip(root: Node, length: float, times: Array, frames: Array) -> void:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	_add(root, root, ap)
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_NONE
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath("Sprite2D:frame"))
	a.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST)
	for i in times.size():
		a.track_insert_key(t, (times[i] as float), frames[i] as int)
	var lib := AnimationLibrary.new()
	lib.add_animation("play", a)
	ap.add_animation_library("", lib)


func _sprite(texture_path: String, hframes: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Sprite2D"
	s.texture = load(texture_path) as Texture2D
	s.hframes = hframes
	s.scale = Vector2.ONE * SPRITE_SCALE
	return s


func _sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = "SkillSfx"
	p.stream = load(path) as AudioStream
	return p


func _build_silk_bind() -> bool:
	# SilkBind.prefab: root scale 1, SpriteRenderer size 4x4 u (256 px frame x 0.25); SilkBind.anim
	# 7 frames of 256, stop time 0.6 s (0.0833 s per frame, last frame held).
	var root := Node2D.new()
	root.name = "SilkBind"
	root.set_script(load("res://scenes/vfx/one_shot_anim.gd"))
	_add(root, root, _sprite("res://assets/player/SilkBind.png", 7))
	_add_frame_clip(root, 0.59999996,
			[0.0, 5 * T, 10 * T, 15 * T, 20 * T, 25 * T, 30 * T, 35 * T],
			[0, 1, 2, 3, 4, 5, 6, 6])
	return _save(root, "res://scenes/vfx/silk_bind.tscn")


func _build_gossamer() -> bool:
	# GossamerSilk.prefab: scale 1, SpriteRenderer size 8x8 u (512 px frame x 0.25), CircleCollider2D
	# trigger r 2.4 u (used as the query circle, radius is an @export on gossamer.gd).
	# GossamerSilk.anim: 10 frames of 512, stop time 0.75 s.
	var root := Node2D.new()
	root.name = "Gossamer"
	root.set_script(load("res://scenes/player/gossamer.gd"))
	_add(root, root, _sprite("res://assets/player/GossamerSilk.png", 10))
	var times: Array = []
	for n: int in [0, 1, 3, 4, 6, 9, 11, 12, 16, 17, 20, 22, 25, 27, 30, 32, 35, 38, 42, 43]:
		times.append(n * T)
	_add_frame_clip(root, 0.75, times, [0, 0, 1, 2, 2, 3, 3, 4, 5, 6, 7, 1, 2, 3, 8, 4, 5, 7, 1, 9])
	_add(root, root, _sfx("res://assets/sfx/gossamer.ogg"))
	return _save(root, "res://scenes/player/gossamer.tscn")


func _build_silk_burst() -> bool:
	# SilkBurst.prefab: BoxCollider2D trigger size (8, 2) u -> 128x32 px, offset 0; sprite 512x128 frames
	# x 0.25 = 128x32 px. SilkBurst.anim: 6 frames, stop time 0.4833 s.
	var root := Area2D.new()
	root.name = "SilkBurst"
	root.set_script(load("res://scenes/player/silk_burst.gd"))
	_add(root, root, _sprite("res://assets/player/SilkBurst.png", 6))
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(128, 32)
	shape.shape = rect
	_add(root, root, shape)
	_add_frame_clip(root, 0.48333335,
			[0.0, 6 * T, 11 * T, 15 * T, 19 * T, 23 * T, 26 * T, 28 * T],
			[0, 1, 2, 3, 3, 4, 5, 5])
	_add(root, root, _sfx("res://assets/sfx/silk_burst.ogg"))
	return _save(root, "res://scenes/player/silk_burst.tscn")


func _build_hud() -> bool:
	# UI.prefab (1920x1080 reference canvas, scaled 1/5 to the 384x216 viewport). Children of the bars
	# are created by hud.gd (they depend on max_hp / lifeblood / max_silk).
	var root := CanvasLayer.new()
	root.name = "HUD"
	root.set_script(load("res://scenes/ui/hud.gd"))
	var masks := HBoxContainer.new()
	masks.name = "Masks"
	_add(root, root, masks)
	var silk_bar := HBoxContainer.new()
	silk_bar.name = "SilkBar"
	_add(root, root, silk_bar)
	var left_cap := TextureRect.new()
	left_cap.name = "LeftCap"
	_add(root, silk_bar, left_cap)
	var segments := HBoxContainer.new()
	segments.name = "Segments"
	_add(root, silk_bar, segments)
	var right_cap := TextureRect.new()
	right_cap.name = "RightCap"
	_add(root, silk_bar, right_cap)
	var shards := Control.new()
	shards.name = "Shards"
	_add(root, root, shards)
	var icon := TextureRect.new()
	icon.name = "Icon"
	_add(root, shards, icon)
	var count := Label.new()
	count.name = "Count"
	_add(root, shards, count)
	return _save(root, "res://scenes/ui/hud.tscn")
