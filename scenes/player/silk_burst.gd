class_name SilkBurst
extends Area2D
## Port of SilkBurst.cs + SilkBurst.prefab (plan 5.13). Child of the player's Visual at local (64, 0),
## so it follows the facing. Damages every enemy that enters it once. Gives no silk.
## Unity: SilkBurst.anim animates BoxCollider2D.enabled 0 -> 1 at t = 0.15 s (stepped), so the hitbox
## only exists for the second half of the 0.483 s VFX clip. Frees itself when the clip ends.

## Physics layer bits (project.godot layer names).
const LAYER_ENEMY: int = 4
const LAYER_PLAYER_ATTACK: int = 8
## Unity: random volume / pitch of every sound effect (plan 5.15), shared with the player.
const SFX_VOLUME_MIN: float = 0.8
const SFX_VOLUME_MAX: float = 1.0
const SFX_PITCH_MIN: float = 0.7
const SFX_PITCH_MAX: float = 1.3

## Unity: SilkBurst.damage (prefab 10).
@export var damage: int = 10
## Unity: SilkBurst.knockbackPower 15 u/s -> px/s.
@export var knockback_power: float = 240.0
## Unity: knockbackForce.y = 5 (impulse up) -> px/s, y flipped.
@export var knockback_up: float = -80.0
## Unity: SilkBurst.anim BoxCollider2D.m_Enabled keyframe 0 -> 1 at 0.15 s.
@export var hitbox_delay: float = 0.15

## Unity: SilkBurst.playerPos, set by Player.ThrowSilkBurst.
var player_pos: Vector2 = Vector2.ZERO

var _age: float = 0.0
var _hitbox_on: bool = false
var _hit_ids: Dictionary = {}

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var shape: CollisionShape2D = $Shape
@onready var sfx: AudioStreamPlayer = $SkillSfx

func _ready() -> void:
	collision_layer = LAYER_PLAYER_ATTACK
	collision_mask = LAYER_ENEMY
	shape.disabled = true
	body_entered.connect(_on_target_entered)
	area_entered.connect(_on_target_entered)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	anim.animation_finished.connect(func(_clip: StringName) -> void: queue_free())
	anim.play(&"play")
	sfx.volume_db = linear_to_db(randf_range(SFX_VOLUME_MIN, SFX_VOLUME_MAX))
	sfx.pitch_scale = randf_range(SFX_PITCH_MIN, SFX_PITCH_MAX)
	sfx.play()

func _physics_process(delta: float) -> void:
	_age += delta
	if not _hitbox_on and _age >= hitbox_delay:
		_hitbox_on = true
		shape.set_deferred("disabled", false)

func _on_target_entered(target: Node) -> void:
	var enemy := target as Enemy
	if enemy == null and target.get_parent() != null:
		enemy = target.get_parent() as Enemy # failsafe / ContactArea
	if enemy == null or enemy.is_dead:
		return
	var id: int = enemy.get_instance_id()
	if _hit_ids.has(id):
		return # body + ContactArea both enter: once per enemy
	_hit_ids[id] = true
	# Unity: (enemy - playerPos).normalized(); knockback = (dir.x * power, 5).
	var dir: Vector2 = (enemy.global_position - player_pos).normalized()
	enemy.damaged(damage, Vector2(dir.x * knockback_power, knockback_up))
