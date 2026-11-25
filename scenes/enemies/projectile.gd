class_name Projectile
extends Area2D
## Port of Projectile.cs (plan 6.4), enemy variant (layer EnemyAttack). Moves itself (no physics
## body); polls its overlaps each physics tick so that i-frames (player Hurtbox off) let it pass.

const LAYER_GROUND: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY_ATTACK: int = 16
const UNITY_GRAVITY: float = 9.81 * 16.0

@export var melee_hittable: bool = false
## Unity: Projectile.durability.
@export var durability: int = 1
@export var damage: int = 1
@export var knockback_able: bool = true
## Unity: maxBounce 0 -> dies on the first contact.
@export var max_bounce: int = 0
## Player.StatusEffect (NONE 0, PARALYZED 1, SLOWED 2, DRAINED 3).
@export var inflict_status: int = 0
## Unity: Destroy(gameObject, 10) from Start.
@export var lifetime: float = 10.0
## Unity: fadeSpeed 10 /s once dead; Destroy 0.5 s after alpha reaches 0 (and 5 s after Death).
@export var fade_speed: float = 10.0
@export var fade_free_delay: float = 0.5
@export var dead_lifetime: float = 5.0
## Unity: Death() gravityScale 1, drag 1.
@export var dead_drag: float = 1.0

var velocity: Vector2 = Vector2.ZERO
var gravity_scale: float = 0.0
var drag: float = 0.0
var is_dead: bool = false
var bounce_counter: int = 0
var current_durability: int = 0

var _age: float = 0.0
var _dead_age: float = 0.0
var _fade_alpha: float = 1.0
var _fade_free_timer: float = 0.0
var _flash_timer: float = 0.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	current_durability = durability
	add_to_group("projectiles")
	collision_layer = LAYER_ENEMY_ATTACK
	collision_mask = LAYER_PLAYER | LAYER_GROUND
	monitoring = true
	monitorable = true

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	velocity.y += UNITY_GRAVITY * gravity_scale * delta
	velocity *= 1.0 / (1.0 + drag * delta)
	global_position += velocity * delta
	if is_dead:
		_tick_dead(delta)
		return
	_check_hits()

func _tick_dead(delta: float) -> void:
	_dead_age += delta
	if _fade_alpha > 0.0:
		_fade_alpha -= fade_speed * delta
		if sprite != null:
			sprite.modulate.a = maxf(_fade_alpha, 0.0)
	else:
		_fade_free_timer += delta
		if _fade_free_timer >= fade_free_delay:
			queue_free()
	if _dead_age >= dead_lifetime:
		queue_free()

## OnCollisionEnter2D: player (damage + status) or ground; every contact counts as a bounce.
func _check_hits() -> void:
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player"):
			if bool(body.get("in_i_frame")) or bool(body.get("is_dead")):
				continue # Physics2D.IgnoreLayerCollision during i-frames: passes through
			bounce_counter += 1
			var dir: Vector2 = (body.global_position - global_position).normalized()
			body.call("damaged", damage, dir)
			body.call("inflicted_status_effect", inflict_status)
		elif body is TileMapLayer or (body is CollisionObject2D and (body.collision_layer & LAYER_GROUND) != 0):
			bounce_counter += 1
		else:
			continue
		if bounce_counter > max_bounce:
			death()
			return

## Projectile.Damaged (only reachable with melee_hittable).
func damaged(amount: int, knockback: Vector2) -> void:
	if knockback_able:
		velocity = knockback
	current_durability -= amount
	if current_durability <= 0:
		death()

func death() -> void:
	if is_dead:
		return
	is_dead = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	gravity_scale = 1.0
	drag = dead_drag
	_dead_age = 0.0
