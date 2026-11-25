class_name ToolProjectile
extends Projectile
## Port of Projectile.cs for the player's thrown tools (ThrowBladeProj / TripleKnifeProj prefabs, layer
## PlayerAttack). Same rules as the Dipsa bullet (projectile.gd): moves itself, dies on its first contact
## (maxBounce 0) with an enemy or the ground, then falls (gravity 1, drag 1) fading out. The difference is
## the target: OnCollisionEnter2D on layer PlayerAttack calls `enemy.Damaged(damage, dir.normalized)`.
## Unity's layer matrix (Physics2DSettings) lets PlayerAttack collide with Ground, Enemy and EnemyAttack;
## the EnemyAttack contact (enemy bullets) is not ported: both projectiles have projectileHittable 0, so
## in Unity the knife only bounces off a bullet without damaging it.

const LAYER_ENEMY: int = 4
const LAYER_PLAYER_ATTACK: int = 8
## Unity passes the normalised direction as the knockback impulse: 1 u/s -> 16 px/s (enemy mass 1).
const KNOCKBACK_IMPULSE: float = 16.0
const COLLIDE_VOLUME_MIN: float = 0.8
const COLLIDE_VOLUME_MAX: float = 1.0
const COLLIDE_PITCH_MIN: float = 0.7
const COLLIDE_PITCH_MAX: float = 1.3

## Enemies hit (test / debug access).
var hit_enemies: Array[Enemy] = []

@onready var shape: CollisionShape2D = $Shape
@onready var collide_sound: AudioStreamPlayer = get_node_or_null("CollideSound") as AudioStreamPlayer

func _ready() -> void:
	super._ready()
	collision_layer = LAYER_PLAYER_ATTACK
	collision_mask = LAYER_ENEMY | LAYER_GROUND

## RedToolController: velocity = direction * speed; `face_left` mirrors sprite and collider
## (Unity: localScale.x = -localScale.x).
func launch(direction: Vector2, speed: float, face_left: bool) -> void:
	velocity = direction * speed
	if face_left:
		var s := get_node("Sprite2D") as Sprite2D
		s.scale.x = -s.scale.x
		var cs := get_node("Shape") as CollisionShape2D
		cs.position.x = -cs.position.x

## OnCollisionEnter2D (layer PlayerAttack): enemies take `damage`, every contact counts as a bounce.
func _check_hits() -> void:
	for body: Node2D in get_overlapping_bodies():
		var enemy := body as Enemy
		if enemy != null:
			if enemy.is_dead:
				continue
			bounce_counter += 1
			_play_collide_sound()
			hit_enemies.append(enemy)
			enemy.damaged(damage, (enemy.global_position - global_position).normalized() * KNOCKBACK_IMPULSE)
		elif body is TileMapLayer or (body is CollisionObject2D and (body.collision_layer & LAYER_GROUND) != 0):
			bounce_counter += 1
			_play_collide_sound()
		else:
			continue
		if bounce_counter > max_bounce:
			death()
			return

func _play_collide_sound() -> void:
	if collide_sound == null:
		return
	collide_sound.volume_db = linear_to_db(randf_range(COLLIDE_VOLUME_MIN, COLLIDE_VOLUME_MAX))
	collide_sound.pitch_scale = randf_range(COLLIDE_PITCH_MIN, COLLIDE_PITCH_MAX)
	collide_sound.play()
