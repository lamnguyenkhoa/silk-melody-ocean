extends SceneTree
## Builds the P3 combat scenes:
##   scenes/player/player_slash.tscn, scenes/vfx/{slash_spark,hurt_spark,slash_pe,hurt_pe}.tscn,
##   scenes/enemies/training_dummy.tscn
## Run: godot --headless --path . -s tools/build_combat.gd   (then re-run tools/build_player.gd)

const SPRITE_SCALE := 0.25

func _initialize() -> void:
	await process_frame # autoloads (GameState) must exist before player_slash.gd / enemy.gd compile
	var ok := true
	ok = _build_slash() and ok
	ok = _build_slash_spark() and ok
	ok = _build_hurt_spark() and ok
	ok = _build_slash_pe() and ok
	ok = _build_hurt_pe() and ok
	ok = _build_training_dummy() and ok
	quit(0 if ok else 1)


func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("build_combat: saved %s (err %d)" % [path, err])
	root.free()
	return err == OK


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node


func _build_slash() -> bool:
	var root := Area2D.new()
	root.name = "PlayerSlash"
	root.set_script(load("res://scenes/player/player_slash.gd"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	_add(root, root, sprite)
	var box := CollisionShape2D.new()
	box.name = "BoxShape"
	_add(root, root, box)
	var poly := CollisionPolygon2D.new()
	poly.name = "PolygonShape"
	_add(root, root, poly)
	return _save(root, "res://scenes/player/player_slash.tscn")


func _make_clip_player(root: Node2D) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	_add(root, root, ap)
	return ap


func _build_slash_spark() -> bool:
	# SlashSpark.prefab: root scale (2, 1); SlashSpark.anim frames 0@0 1@0.0333 2@0.1 3@0.1667, len 0.2167.
	# SlashSpark.png is 4 stacked 512x64 frames.
	var root := Node2D.new()
	root.name = "SlashSpark"
	root.set_script(load("res://scenes/vfx/one_shot_anim.gd"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://assets/player/SlashSpark.png")
	sprite.hframes = 1
	sprite.vframes = 4
	sprite.scale = Vector2(2.0, 1.0) * SPRITE_SCALE
	_add(root, root, sprite)
	var ap := _make_clip_player(root)
	var a := Animation.new()
	a.length = 0.21666667
	a.loop_mode = Animation.LOOP_NONE
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath("Sprite2D:frame"))
	a.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST)
	for kv: Array in [[0.0, 0], [0.033333335, 1], [0.1, 2], [0.16666667, 3]]:
		a.track_insert_key(t, kv[0] as float, kv[1] as int)
	var lib := AnimationLibrary.new()
	lib.add_animation("play", a)
	ap.add_animation_library("", lib)
	return _save(root, "res://scenes/vfx/slash_spark.tscn")


func _build_hurt_spark() -> bool:
	# HurtSpark.prefab: root scale (2, 1.5); HurtSpark.anim: scale (2,1.5) -> (3,1.5) and
	# alpha 1 -> 0 over 0.25 s.
	var root := Node2D.new()
	root.name = "HurtSpark"
	root.set_script(load("res://scenes/vfx/one_shot_anim.gd"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://assets/player/HurtSpark.png")
	sprite.scale = Vector2(2.0, 1.5) * SPRITE_SCALE
	_add(root, root, sprite)
	var ap := _make_clip_player(root)
	var a := Animation.new()
	a.length = 0.25
	a.loop_mode = Animation.LOOP_NONE
	var ts := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ts, NodePath("Sprite2D:scale"))
	a.track_insert_key(ts, 0.0, Vector2(2.0, 1.5) * SPRITE_SCALE)
	a.track_insert_key(ts, 0.25, Vector2(3.0, 1.5) * SPRITE_SCALE)
	var ta := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ta, NodePath("Sprite2D:modulate:a"))
	a.track_insert_key(ta, 0.0, 1.0)
	a.track_insert_key(ta, 0.25, 0.0)
	var lib := AnimationLibrary.new()
	lib.add_animation("play", a)
	ap.add_animation_library("", lib)
	return _save(root, "res://scenes/vfx/hurt_spark.tscn")


func _particles(node_name: String, with_script: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	if with_script:
		p.set_script(load("res://scenes/vfx/one_shot_particles.gd"))
	p.emitting = false
	p.one_shot = true
	p.gravity = Vector2.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	return p


func _build_slash_pe() -> bool:
	# SlashPE.prefab: burst of 5, cone angle 20 deg. Speed/size/lifetime are an approximation of the
	# Unity curves (tune by eye); direction is set by the spawner (along the knockback).
	var p := _particles("SlashPE", true)
	p.amount = 5
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 20.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.0
	p.color = Color(1.0, 0.95, 0.75)
	return _save(p, "res://scenes/vfx/slash_pe.tscn")


func _build_hurt_pe() -> bool:
	# HurtPE.prefab: burst of 10, cone angle 90 (all around), start size 0.4 u. Approximation.
	var p := _particles("HurtPE", true)
	p.amount = 10
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Color(1.0, 0.85, 0.85)
	return _save(p, "res://scenes/vfx/hurt_pe.tscn")


func _build_training_dummy() -> bool:
	# Debug dummy: Enemy base, hp 999, gravity_scale 1, drag 1, contact damage ON.
	# Body / contact box = Crawling.prefab body (Rect 18.1 x 10.5) placed at the bottom of the
	# sprite content (content centre is ~9.5 px below the frame centre).
	var root := CharacterBody2D.new()
	root.name = "TrainingDummy"
	root.set_script(load("res://scenes/enemies/enemy.gd"))
	root.set("max_hp", 999)
	root.set("gravity_scale", 1.0)
	root.set("drag", 1.0)
	root.set("no_contact_damage", false)
	root.set("enemy_type", 99)
	var body := CollisionShape2D.new()
	body.name = "Body"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18.1, 10.5)
	body.shape = rect
	body.position = Vector2(0, 9.5)
	_add(root, root, body)
	var visual := Node2D.new()
	visual.name = "Visual"
	_add(root, root, visual)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://assets/enemies/Crawling.png")
	sprite.hframes = 4
	sprite.frame = 0
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	_add(root, visual, sprite)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	_add(root, root, contact)
	var cshape := CollisionShape2D.new()
	cshape.name = "Shape"
	var crect := RectangleShape2D.new()
	crect.size = Vector2(18.1, 10.5)
	cshape.shape = crect
	cshape.position = Vector2(0, 9.5)
	_add(root, contact, cshape)
	var loot_pos := Marker2D.new()
	loot_pos.name = "LootPos"
	_add(root, root, loot_pos)
	# Plain reusable particles (restarted by Enemy._play_particles), no self-free script.
	var hp := _particles("HitParticles", false)
	hp.amount = 6
	hp.lifetime = 0.35
	hp.explosiveness = 1.0
	hp.spread = 30.0
	hp.initial_velocity_min = 60.0
	hp.initial_velocity_max = 140.0
	hp.scale_amount_min = 1.5
	hp.scale_amount_max = 2.5
	hp.color = Color(1, 1, 1)
	_add(root, root, hp)
	var sfx := AudioStreamPlayer.new()
	sfx.name = "HitSfx"
	sfx.stream = load("res://assets/sfx/hit_enemy.ogg")
	_add(root, root, sfx)
	return _save(root, "res://scenes/enemies/training_dummy.tscn")
