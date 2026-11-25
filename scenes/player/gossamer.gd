class_name Gossamer
extends Node2D
## Port of Gossamer.cs + GossamerSilk.prefab (plan 5.13). Child of the player's Visual at local (4, 0).
## Every [member damage_interval] s damages every enemy inside a circle around its SPAWN position
## (Unity computes the centre once in Start). Gives no silk. Frees itself when the 0.75 s VFX clip ends.

## Physics layer bit (project.godot layer names): Enemy = layer 3.
const LAYER_ENEMY: int = 4
## Unity: random volume / pitch of every sound effect (plan 5.15), shared with the player.
const SFX_VOLUME_MIN: float = 0.8
const SFX_VOLUME_MAX: float = 1.0
const SFX_PITCH_MIN: float = 0.7
const SFX_PITCH_MAX: float = 1.3
## Upper bound of overlap results per query.
const MAX_QUERY_RESULTS: int = 32

## Unity: Gossamer.damageInterval (prefab 0.1 s).
@export var damage_interval: float = 0.1
## Unity: Gossamer.damage (prefab 3).
@export var damage: int = 3
## Unity: CircleCollider2D radius 2.4 u * 16 px (prefab scale 1).
@export var radius: float = 38.4
## Unity: knockbackForce * 0.01 u -> px/s (negligible, but non-zero so the enemy is "knocked").
@export var knockback_power: float = 0.16

## Unity: Gossamer.playerPos, set by Player.BeginGossamer before the first tick.
var player_pos: Vector2 = Vector2.ZERO
## Enemies damaged so far, per tick (test hook).
var tick_count: int = 0

var _timer: float = 0.0
var _center: Vector2 = Vector2.ZERO
var _shape := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sfx: AudioStreamPlayer = $SkillSfx

func _ready() -> void:
	_center = global_position
	_shape.radius = radius
	_query.shape = _shape
	_query.collision_mask = LAYER_ENEMY
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_query.transform = Transform2D(0.0, _center)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	anim.animation_finished.connect(func(_clip: StringName) -> void: queue_free())
	anim.play(&"play")
	sfx.volume_db = linear_to_db(randf_range(SFX_VOLUME_MIN, SFX_VOLUME_MAX))
	sfx.pitch_scale = randf_range(SFX_PITCH_MIN, SFX_PITCH_MAX)
	sfx.play()

func _physics_process(delta: float) -> void:
	_timer += delta
	# Unity: `if (timer > damageInterval) { timer = 0; ... }` (strict >, reset to 0).
	if _timer > damage_interval:
		_timer = 0.0
		_damage_enemies_in_circle()

func _damage_enemies_in_circle() -> void:
	tick_count += 1
	var space := get_world_2d().direct_space_state
	var seen: Dictionary = {}
	for hit: Dictionary in space.intersect_shape(_query, MAX_QUERY_RESULTS):
		var node := hit["collider"] as Node
		var enemy := node as Enemy
		if enemy == null and node != null and node.get_parent() != null:
			enemy = node.get_parent() as Enemy # failsafe (collider inside a holder node)
		if enemy == null or enemy.is_dead or seen.has(enemy):
			continue # body + ContactArea of one enemy both overlap: one hit per enemy per tick
		seen[enemy] = true
		var knockback: Vector2 = (enemy.global_position - player_pos).normalized() * knockback_power
		enemy.damaged(damage, knockback)
