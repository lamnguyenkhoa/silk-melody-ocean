class_name PlayerSlash
extends Area2D
## Port of PlayerSlash.cs + SlashPrefab / DashSlashPrefab / PogoSlashPrefab (plan 5.9).
## One scene, three variants selected by [member variant] (call [method setup] BEFORE add_child).
## Layer PlayerAttack; mask Enemy + EnemyAttack + Ground.

enum Kind { SLASH, DASH_SLASH, POGO_SLASH }

## Physics layer bits (project.godot layer names).
const LAYER_GROUND: int = 1
const LAYER_PLAYER_ATTACK: int = 8
const LAYER_ENEMY: int = 4
const LAYER_ENEMY_ATTACK: int = 16

## Unity: PlayerSlash.Update sets fadeSpeedAccel = 100 once the hitbox is over (all variants).
const FADE_ACCEL_AFTER_HIT: float = 100.0
## Unity: Destroy(gameObject, 1f) once alpha reaches 0.
const FREE_DELAY: float = 1.0
## Unity: slash spark random rotation +-10 deg.
const SPARK_ROTATION_DEG: float = 10.0
## Sprites are PPU 64 -> x0.25 (plan 0).
const SPRITE_SCALE: float = 0.25

const SLASH_SPARK_SCENE := "res://scenes/vfx/slash_spark.tscn"
const SLASH_PE_SCENE := "res://scenes/vfx/slash_pe.tscn"

## Variant table. Collider values are the prefab BoxCollider2D (size, offset) x16, y negated.
## knockback < 0 means "use GameState.enemy_knockback_power" (normal slash, set by Player.cs).
## lifetime < 0 means "GameState.dash_time" (Player.cs sets disappearTime = dashTime).
const VARIANT_DATA: Dictionary = {
	# SlashPrefab: BoxCollider2D size (2.3594, 1.6226) offset (0.5174, -0.1015); knockbackPower 1
	# (overridden by Player.AttackDealDamage), fadeSpeedAccel 100, disappearTime 0.15.
	Kind.SLASH: {
		"texture": "res://assets/player/Slash.png",
		"size": Vector2(37.7504, 25.9611), "offset": Vector2(8.27849, 1.62360),
		"knockback": -1.0, "has_recoil": false, "can_reset_dash": false, "is_dash_attack": false,
		"fade_accel": 100.0, "lifetime": 0.15,
	},
	# DashSlashPrefab: BoxCollider2D size (1.6157, 0.7235) offset (-0.0237, 0.1025); knockbackPower 1,
	# fadeSpeedAccel 10, hasRecoil 1, isDashAttack 1.
	Kind.DASH_SLASH: {
		"texture": "res://assets/player/DashSlash.png",
		"size": Vector2(25.8520, 11.5768), "offset": Vector2(-0.37930, -1.63929),
		"knockback": 16.0, "has_recoil": true, "can_reset_dash": false, "is_dash_attack": true,
		"fade_accel": 10.0, "lifetime": -1.0,
	},
	# PogoSlashPrefab: PolygonCollider2D m_Points below; knockbackPower 1, fadeSpeedAccel 10,
	# canResetDash 1, hasRecoil 1, isDashAttack 1.
	Kind.POGO_SLASH: {
		"texture": "res://assets/player/PogoSlash.png",
		"size": Vector2.ZERO, "offset": Vector2.ZERO,
		"knockback": 16.0, "has_recoil": true, "can_reset_dash": true, "is_dash_attack": true,
		"fade_accel": 10.0, "lifetime": -1.0,
	},
}

## PogoSlashPrefab.prefab m_Points (-1.2657,-0.1599) (0.8152,-0.9964) (-0.4546,1.0870) x16, y negated.
const POGO_POLYGON: PackedVector2Array = [
	Vector2(-20.25116, 2.55835), Vector2(13.04340, 15.94178), Vector2(-7.27310, -17.39159),
]

var variant: Kind = Kind.SLASH
var player: Player
var knockback_power: float = 16.0
var has_recoil: bool = false
var can_reset_dash: bool = false
var is_dash_attack: bool = false
## Used for the parry riposte: hits several enemies, never recoils.
var piercing: bool = false
var disappear_time: float = 0.15
var fade_accel: float = 100.0

var _timer: float = 0.0
var _impacted: bool = false
var _alpha: float = 1.0
var _fade_speed: float = 0.0
var _free_timer: float = 0.0
var _hitbox_active: bool = true
var _hit_ids: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var box_shape: CollisionShape2D = $BoxShape
@onready var polygon_shape: CollisionPolygon2D = $PolygonShape

## Applies the variant table. Call before add_child; the caller may then override
## has_recoil / piercing / knockback_power (like Player.cs does after Instantiate).
func setup(owner_player: Player, which: Kind) -> void:
	player = owner_player
	variant = which
	var d: Dictionary = VARIANT_DATA[which]
	var kb: float = d["knockback"]
	knockback_power = GameState.enemy_knockback_power if kb < 0.0 else kb
	has_recoil = d["has_recoil"]
	can_reset_dash = d["can_reset_dash"]
	is_dash_attack = d["is_dash_attack"]
	fade_accel = d["fade_accel"]
	var life: float = d["lifetime"]
	disappear_time = GameState.dash_time if life < 0.0 else life

func _ready() -> void:
	collision_layer = LAYER_PLAYER_ATTACK
	collision_mask = LAYER_ENEMY | LAYER_ENEMY_ATTACK | LAYER_GROUND
	var d: Dictionary = VARIANT_DATA[variant]
	sprite.texture = load(d["texture"] as String) as Texture2D
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	if variant == Kind.POGO_SLASH:
		box_shape.disabled = true
		polygon_shape.polygon = POGO_POLYGON
		polygon_shape.disabled = false
	else:
		var rect := RectangleShape2D.new()
		rect.size = d["size"]
		box_shape.shape = rect
		box_shape.position = d["offset"]
		box_shape.disabled = false
		polygon_shape.disabled = true
	if piercing and has_recoil:
		push_warning("PlayerSlash: piercing and has_recoil are mutually exclusive")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_timer += delta
	if _impacted or _timer >= disappear_time:
		if _hitbox_active:
			_hitbox_active = false
			box_shape.set_deferred("disabled", true)
			polygon_shape.set_deferred("disabled", true)
		fade_accel = FADE_ACCEL_AFTER_HIT
	if _alpha > 0.0:
		_alpha = clampf(_alpha - _fade_speed * delta, 0.0, 1.0)
		sprite.modulate.a = _alpha
		_fade_speed += fade_accel * delta
	else:
		_free_timer += delta
		if _free_timer >= FREE_DELAY:
			queue_free()

func _on_area_entered(area: Area2D) -> void:
	_handle_target(area)

func _on_body_entered(body: Node2D) -> void:
	_handle_target(body)

func _handle_target(node: Node) -> void:
	var enemy := node as Enemy
	if enemy == null and node.get_parent() != null:
		enemy = node.get_parent() as Enemy # failsafe (collider inside a holder node)
	if enemy != null:
		_hit_enemy(enemy)
		return
	var projectile: Node = _find_projectile(node)
	if projectile != null:
		if bool(projectile.get("melee_hittable")):
			if not _impacted:
				_enemy_impact_effect()
			var kb: Vector2 = _knockback_toward(projectile)
			projectile.call("damaged", GameState.damage, kb)
		return
	if _is_ground(node) and is_dash_attack:
		player.dash_attack_touch_ground()
		if not piercing:
			_impacted = true

## Ground = the collision TileMapLayer (not a CollisionObject2D in Godot 4) or any body on the Ground layer.
func _is_ground(node: Node) -> bool:
	if node is TileMapLayer:
		return true
	var collider := node as CollisionObject2D
	return collider != null and (collider.collision_layer & LAYER_GROUND) != 0

## P5 will add the Projectile class; until then it is duck-typed (EnemyAttack layer,
## `melee_hittable` property and `damaged` method).
func _find_projectile(node: Node) -> Node:
	var collider := node as CollisionObject2D
	if collider == null or (collider.collision_layer & LAYER_ENEMY_ATTACK) == 0:
		return null
	for candidate: Node in [node, node.get_parent()]:
		if candidate != null and candidate.has_method("damaged") and "melee_hittable" in candidate:
			return candidate
	return null

func _enemy_impact_effect() -> void:
	_impacted = true
	# If piercing (attack multiple enemies) then no recoil.
	if not piercing and has_recoil:
		player.attack_recoil(can_reset_dash)

func _knockback_toward(target: Node2D) -> Vector2:
	return (target.global_position - player.global_position).normalized() * knockback_power

func _hit_enemy(enemy: Enemy) -> void:
	var id: int = enemy.get_instance_id()
	if _hit_ids.has(id) or enemy.is_dead:
		return # one hit per enemy per slash (the body and its ContactArea both overlap)
	_hit_ids[id] = true
	if not _impacted:
		_enemy_impact_effect()
	var knockback: Vector2 = _knockback_toward(enemy)
	enemy.damaged(GameState.damage, knockback)
	_spawn_hit_effects(enemy.global_position, knockback)
	GameState.add_silk(1)

func _spawn_hit_effects(pos: Vector2, knockback: Vector2) -> void:
	var host: Node = player.get_parent()
	if host == null:
		return
	# Unity: LookRotation(forward, rot(90 + rand) * knockback) makes the spark's X axis point
	# along the knockback direction (+- 10 deg).
	var spark := load(SLASH_SPARK_SCENE) as PackedScene
	var spark_node := spark.instantiate() as Node2D
	spark_node.global_position = pos
	spark_node.rotation = knockback.angle() + deg_to_rad(randf_range(-SPARK_ROTATION_DEG, SPARK_ROTATION_DEG))
	host.add_child(spark_node)
	var pe := (load(SLASH_PE_SCENE) as PackedScene).instantiate() as CPUParticles2D
	pe.global_position = pos
	pe.direction = knockback.normalized()
	host.add_child(pe)
	pe.emitting = true
