extends SceneTree
## Builds the P5 scenes:
##   scenes/loot/loot.tscn (copper shard), scenes/enemies/projectile.tscn (Dipsa bullet),
##   scenes/enemies/{crawling,dipsa,crabber}.tscn
## Run: godot --headless --path . -s tools/build_enemies.gd
## (order: build_combat, build_skills, build_player, build_enemies, build_rooms)
## Sprite tables come from the .png.meta sprite rects (trimmed sprites, pivot = rect centre) and the
## Idle / Attack .anim m_PPtrCurves in Assets/Enemy/*. Unity prefab values are in the comments.

const SPRITE_SCALE := 0.25
const SPRITE_DIR := "res://assets/enemies/"
const LOOT_SCENE := "res://scenes/loot/loot.tscn"
const BULLET_SCENE := "res://scenes/enemies/projectile.tscn"
const ENEMY_SCRIPT_DIR := "res://scenes/enemies/"

## Atlas frames [x, y, w, h] in image px (y from the top).
const CRAWLING_FRAMES := [[27, 81, 74, 42], [155, 85, 75, 39], [284, 87, 71, 36], [411, 85, 75, 39]]
const DIPSA_FRAMES := [[0, 0, 128, 128], [128, 0, 128, 128], [256, 0, 128, 128], [384, 0, 128, 128]]
const CRABBER_FRAMES := [[40, 50, 86, 76], [167, 53, 85, 71], [298, 50, 83, 74], [414, 45, 98, 80],
		[517, 48, 114, 77], [653, 48, 111, 78]]
const BULLET_FRAME := [0, 0, 32, 32]

## Idle.anim key spacing (1/6 s).
const STEP := 1.0 / 6.0


func _initialize() -> void:
	await process_frame # autoloads must exist before enemy.gd compiles
	var ok := true
	ok = _build_loot() and ok
	ok = _build_projectile() and ok
	ok = _build_crawling() and ok
	ok = _build_dipsa() and ok
	ok = _build_crabber() and ok
	quit(0 if ok else 1)


func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("build_enemies: saved %s (err %d)" % [path, err])
	root.free()
	return err == OK


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node


func _atlas(png: String, f: Array) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = load(SPRITE_DIR + png) as Texture2D
	t.region = Rect2(f[0] as int, f[1] as int, f[2] as int, f[3] as int)
	return t


func _particles(node_name: String) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.emitting = false
	p.one_shot = true
	p.gravity = Vector2.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	return p


func _rect_shape(size: Vector2, pos: Vector2, shape_name: String) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	cs.name = shape_name
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = pos
	return cs


func _circle_shape(radius: float, pos: Vector2, shape_name: String) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	cs.name = shape_name
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	cs.position = pos
	return cs


## Clip with a texture track (AtlasTexture frame per key) and optional method events on the root.
func _clip(frames: Array, times: Array, indices: Array, length: float, loops: bool, events: Dictionary = {}) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath("Visual/Sprite2D:texture"))
	a.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE)
	for i in times.size():
		a.track_insert_key(t, times[i] as float, frames[indices[i] as int])
	if not events.is_empty():
		var m := a.add_track(Animation.TYPE_METHOD)
		a.track_set_path(m, NodePath("."))
		for time: float in events:
			a.track_insert_key(m, time, {"method": StringName(events[time] as String), "args": []})
	return a


## Common enemy skeleton: body + ContactArea (same shape), Visual/Sprite2D/AnimationPlayer, LootPos,
## HitParticles, HitSfx. [param make_shape] is a Callable(name) -> CollisionShape2D.
func _enemy(root_name: String, script_name: String, make_shape: Callable, frames: Array, sprite_pos: Vector2) -> Dictionary:
	var root := CharacterBody2D.new()
	root.name = root_name
	root.set_script(load(ENEMY_SCRIPT_DIR + script_name))
	_add(root, root, make_shape.call("Body") as Node)
	var visual := Node2D.new()
	visual.name = "Visual"
	_add(root, root, visual)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.position = sprite_pos
	sprite.texture = frames[0]
	_add(root, visual, sprite)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.root_node = NodePath("../..")
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	ap.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_add(root, visual, ap)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	_add(root, root, contact)
	_add(root, contact, make_shape.call("Shape") as Node)
	var loot_pos := Marker2D.new()
	loot_pos.name = "LootPos"
	_add(root, root, loot_pos)
	var hp := _particles("HitParticles")
	hp.amount = 6
	hp.lifetime = 0.35
	hp.explosiveness = 1.0
	hp.spread = 30.0
	hp.initial_velocity_min = 60.0
	hp.initial_velocity_max = 140.0
	hp.scale_amount_min = 1.5
	hp.scale_amount_max = 2.5
	_add(root, root, hp)
	var sfx := AudioStreamPlayer.new()
	sfx.name = "HitSfx"
	sfx.stream = load("res://assets/sfx/hit_enemy.ogg")
	_add(root, root, sfx)
	return {"root": root, "ap": ap}


func _idle_clip(frames: Array, key_indices: Array, length: float) -> Animation:
	var times: Array = []
	for i in key_indices.size():
		times.append(minf(i * STEP, length))
	return _clip(frames, times, key_indices, length, true)


func _finish_enemy(d: Dictionary, lib: AnimationLibrary) -> void:
	var ap: AnimationPlayer = d["ap"]
	ap.add_animation_library("", lib)
	ap.autoplay = "idle"


func _build_loot() -> bool:
	# CopperShardSmall.prefab: layer Loot, gravityScale 2, drag 1, Box 0.3597 x 0.4281 @ (0.0188, 0.0051),
	# Loot.cs value 1, destroyTime 20, animSpeed 5.
	var root := CharacterBody2D.new()
	root.name = "CopperShardSmall"
	root.set_script(load("res://scenes/loot/loot.gd"))
	var shape_pos := Vector2(0.018823862 * 16.0, -0.0051338077 * 16.0)
	var shape_size := Vector2(0.35967588 * 16.0, 0.4281267 * 16.0)
	_add(root, root, _rect_shape(shape_size, shape_pos, "Body"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://assets/props/CopperShard.png") as Texture2D
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	_add(root, root, sprite)
	var area := Area2D.new()
	area.name = "PickupArea"
	_add(root, root, area)
	_add(root, area, _rect_shape(shape_size, shape_pos, "Shape"))
	var sfx := AudioStreamPlayer.new()
	sfx.name = "PickupSfx"
	sfx.stream = load("res://assets/sfx/loot_pickup.ogg")
	_add(root, root, sfx)
	return _save(root, LOOT_SCENE)


func _build_projectile() -> bool:
	# NormalDipsaBullet.prefab: layer EnemyAttack, Circle r 0.1, sprite Bullet_0 size 0.5 tinted
	# (1, 0.524, 0.0415), damage 1, durability 1, maxBounce 0, meleeHittable false.
	var root := Area2D.new()
	root.name = "NormalDipsaBullet"
	root.set_script(load("res://scenes/enemies/projectile.gd"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = _atlas("DipsaBullet.png", BULLET_FRAME)
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.modulate = Color(1.0, 0.5240712, 0.04150939)
	_add(root, root, sprite)
	_add(root, root, _circle_shape(0.1 * 16.0, Vector2.ZERO, "Shape"))
	return _save(root, BULLET_SCENE)


func _build_crawling() -> bool:
	# Crawling.prefab: hp 8, type 0, drop 3, gravity 1, drag 1, Box 1.1317 x 0.6584 @ (-0.0131, 0.0165).
	var frames: Array = []
	for f: Array in CRAWLING_FRAMES:
		frames.append(_atlas("Crawling.png", f))
	var shape_maker := func(n: String) -> CollisionShape2D:
		return _rect_shape(Vector2(1.1317244 * 16.0, 0.6584108 * 16.0), Vector2(-0.013144255 * 16.0, -0.016530395 * 16.0), n)
	var d := _enemy("Crawling", "crawling.gd", shape_maker, frames, Vector2.ZERO)
	var root: CharacterBody2D = d["root"]
	root.set("max_hp", 8)
	root.set("enemy_type", 0)
	root.set("drop_amount", 3)
	root.set("gravity_scale", 1.0)
	root.set("drag", 1.0)
	root.set("loot_scene", load(LOOT_SCENE))
	var lib := AnimationLibrary.new()
	# Idle.anim: frames 0,1,2,3,3 at 0 / 1/6 / 1/3 / 0.5 / 0.667, length 0.6833, loop.
	lib.add_animation("idle", _idle_clip(frames, [0, 1, 2, 3], 0.68333334))
	_finish_enemy(d, lib)
	return _save(root, ENEMY_SCRIPT_DIR + "crawling.tscn")


func _build_dipsa() -> bool:
	# Dipsa.prefab: hp 8, type 1, drop 5, gravity 0, drag 1.5, Circle r 0.5; ShootPos (-0.24, -0.8);
	# DipsaAI: timeBetweenAttack 3, bulletSpeed 5, detectionRadius 10; RbPathfindAI speed 250 (flying).
	var frames: Array = []
	for f: Array in DIPSA_FRAMES:
		frames.append(_atlas("NormalDipsa.png", f))
	var shape_maker := func(n: String) -> CollisionShape2D:
		return _circle_shape(0.5 * 16.0, Vector2.ZERO, n)
	var d := _enemy("Dipsa", "dipsa.gd", shape_maker, frames, Vector2.ZERO)
	var root: CharacterBody2D = d["root"]
	root.set("max_hp", 8)
	root.set("enemy_type", 1)
	root.set("drop_amount", 5)
	root.set("gravity_scale", 0.0)
	root.set("drag", 1.5)
	root.set("loot_scene", load(LOOT_SCENE))
	root.set("bullet_scene", load(BULLET_SCENE))
	var shoot := Marker2D.new()
	shoot.name = "ShootPos"
	shoot.position = Vector2(-0.24 * 16.0, 0.8 * 16.0)
	_add(root, root, shoot)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _idle_clip(frames, [0, 1, 2, 3], 0.68333334))
	_finish_enemy(d, lib)
	return _save(root, ENEMY_SCRIPT_DIR + "dipsa.tscn")


func _build_crabber() -> bool:
	# Crabber.prefab: hp 12, type 3, drop 4, gravity 1, drag 1, Box 1.1124 x 0.6359; Sprite at (0, 0.3);
	# CrabberAI: timeBetweenAttack 3, detectionRadius 6, attackRadius 3, dashAttackForce 300.
	var frames: Array = []
	for f: Array in CRABBER_FRAMES:
		frames.append(_atlas("Crabber.png", f))
	var shape_maker := func(n: String) -> CollisionShape2D:
		return _rect_shape(Vector2(1.1124048 * 16.0, 0.6358527 * 16.0), Vector2.ZERO, n)
	var d := _enemy("Crabber", "crabber.gd", shape_maker, frames, Vector2(0.0, -0.3 * 16.0))
	var root: CharacterBody2D = d["root"]
	root.set("max_hp", 12)
	root.set("enemy_type", 3)
	root.set("drop_amount", 4)
	root.set("gravity_scale", 1.0)
	root.set("drag", 1.0)
	root.set("loot_scene", load(LOOT_SCENE))
	var lib := AnimationLibrary.new()
	# Idle.anim: Crabber_0,1,2,2 at 0 / 1/6 / 1/3 / 0.5, length 0.5167, loop.
	lib.add_animation("idle", _idle_clip(frames, [0, 1, 2], 0.51666665))
	# Attack.anim: Crabber_3,4,3,5,5 at 0 / 1/3 / 2/3 / 1 / 1.333, length 1.35, no loop;
	# events BeginAttack 0, DashForward 1/3 and 1.0, EndAttack 1.3333.
	lib.add_animation("attack", _clip(frames, [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0], [3, 4, 3, 5], 1.35, false, {
			0.0: "begin_attack", 0.33333334: "dash_forward", 1.0: "dash_forward", 1.3333334: "end_attack"}))
	_finish_enemy(d, lib)
	return _save(root, ENEMY_SCRIPT_DIR + "crabber.tscn")
