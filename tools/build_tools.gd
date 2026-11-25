extends SceneTree
## Builds the M2 scenes: scenes/player/throw_blade_proj.tscn, triple_knife_proj.tscn and
## scenes/vfx/lifeblood_pe.tscn. Run before build_player (the Player scene references the controller script):
##   godot --headless --path . -s tools/build_tools.gd
## Values from Assets/Inventory/TalismanTab/RedTool/*Proj.prefab (Unity units * 16 px, y negated):
##   BoxCollider2D size (1.0465746, 0.43514824), offset (0.0232873, -0.0044775); sprite ThrowBladeProjectile
##   (64 px, PPU 64 -> scale 0.25). ThrowBladeProj: transform scale 1.5, damage 3. TripleKnifeProj: scale 1,
##   damage 1. Both: Rigidbody2D gravityScale 0, mass 0.001, Projectile maxBounce 0, layer PlayerAttack,
##   CollideSound = knife_collide.ogg. LifebloodNeedlePE: burst 10, lifetime 1 s, speed 6..18 u/s,
##   size 0.2..0.4 u, cone 45 deg, colour (0, 0.855, 1)..(0, 0.29, 1) fading out, gravity 1.

const SPRITE_PATH := "res://assets/player/ThrowBladeProjectile.png"
const SFX_PATH := "res://assets/sfx/knife_collide.ogg"
const SPRITE_SCALE := 0.25
const COLLIDER_SIZE := Vector2(1.0465746, 0.43514824) * 16.0
const COLLIDER_OFFSET := Vector2(0.023287296, 0.004477501) * 16.0

func _initialize() -> void:
	await process_frame # autoloads must exist before the scripts compile
	var ok := true
	ok = _build_projectile("ThrowBladeProj", 3, 1.5, "res://scenes/player/throw_blade_proj.tscn") and ok
	ok = _build_projectile("TripleKnifeProj", 1, 1.0, "res://scenes/player/triple_knife_proj.tscn") and ok
	ok = _build_lifeblood_pe() and ok
	quit(0 if ok else 1)

func _save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("build_tools: saved %s (err %d)" % [path, err])
	root.free()
	return err == OK

func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node

func _build_projectile(node_name: String, damage: int, scale_factor: float, out_path: String) -> bool:
	var root := Area2D.new()
	root.name = node_name
	root.set_script(load("res://scenes/player/tool_projectile.gd"))
	root.set("damage", damage)
	root.set("max_bounce", 0)
	root.set("durability", 1)
	root.set("knockback_able", true)
	root.collision_layer = 8
	root.collision_mask = 5 # Ground + Enemy
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load(SPRITE_PATH)
	sprite.scale = Vector2.ONE * SPRITE_SCALE * scale_factor
	_add(root, root, sprite)
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = COLLIDER_SIZE * scale_factor
	shape.shape = rect
	shape.position = COLLIDER_OFFSET * scale_factor
	_add(root, root, shape)
	var sfx := AudioStreamPlayer.new()
	sfx.name = "CollideSound"
	sfx.stream = load(SFX_PATH)
	_add(root, root, sfx)
	return _save(root, out_path)

func _build_lifeblood_pe() -> bool:
	var p := CPUParticles2D.new()
	p.name = "LifebloodNeedlePE"
	p.set_script(load("res://scenes/vfx/one_shot_particles.gd"))
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.direction = Vector2(-1.0, -0.2)
	p.spread = 45.0
	p.gravity = Vector2(0.0, 9.81 * 16.0)
	p.initial_velocity_min = 6.0 * 16.0
	p.initial_velocity_max = 18.0 * 16.0
	p.scale_amount_min = 0.2 * 16.0
	p.scale_amount_max = 0.4 * 16.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.0, 0.855, 1.0, 1.0))
	ramp.set_color(1, Color(0.0, 0.29, 1.0, 1.0))
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return _save(p, "res://scenes/vfx/lifeblood_pe.tscn")
