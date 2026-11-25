class_name Loot
extends CharacterBody2D
## Port of Loot.cs + CopperShardSmall.prefab (plan 6.6). Falls with gravity_scale 2 / drag 1 and
## is picked up by the player's PlayerTrigger area.

enum LootType { COPPER_SHARD, SCALE_SHARD }

const LAYER_GROUND: int = 1
const LAYER_LOOT: int = 32
const LAYER_PLAYER_TRIGGER: int = 128
const UNITY_GRAVITY: float = 9.81 * 16.0
const PICKUP_SFX_PATH := "res://assets/sfx/loot_pickup.ogg"

@export var loot_type: LootType = LootType.COPPER_SHARD
@export var value: int = 1
## Unity: destroyTime 20 s (0 = never).
@export var destroy_time: float = 20.0
## Unity: animSpeed 5.
@export var anim_speed: float = 5.0
## Unity: Rigidbody2D gravityScale 2, linearDrag 1.
@export var gravity_scale: float = 2.0
@export var drag: float = 1.0
## Unity default material friction (see Enemy.GROUND_FRICTION).
@export var friction: float = 0.4
## Unity: Destroy(gameObject, 1) after pickup.
@export var picked_free_delay: float = 1.0
## Unity: spin scale = sin(randomTmp + Time.time * animSpeed), randomTmp in [90, 270].
@export var spin_phase_min: float = 90.0
@export var spin_phase_max: float = 270.0

var picked_up: bool = false

var _spin_phase: float = 0.0
var _time: float = 0.0
var _sprite_scale: float = 0.25

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_area: Area2D = $PickupArea
@onready var pickup_sfx: AudioStreamPlayer = get_node_or_null("PickupSfx") as AudioStreamPlayer

func _ready() -> void:
	add_to_group("loot")
	collision_layer = LAYER_LOOT
	collision_mask = LAYER_GROUND
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = LAYER_PLAYER_TRIGGER
	pickup_area.area_entered.connect(_on_pickup_area_entered)
	_sprite_scale = absf(sprite.scale.x)
	_spin_phase = randf_range(spin_phase_min, spin_phase_max)
	if pickup_sfx != null and pickup_sfx.stream == null:
		pickup_sfx.stream = load(PICKUP_SFX_PATH) as AudioStream
	if destroy_time > 0.0:
		get_tree().create_timer(destroy_time).timeout.connect(_on_destroy_timeout)

func _on_destroy_timeout() -> void:
	if is_inside_tree():
		queue_free()

func _process(delta: float) -> void:
	_time += delta
	sprite.scale.x = _sprite_scale * sin(_spin_phase + _time * anim_speed)

func _physics_process(delta: float) -> void:
	velocity.y += UNITY_GRAVITY * gravity_scale * delta
	velocity *= 1.0 / (1.0 + drag * delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * UNITY_GRAVITY * gravity_scale * delta)
	move_and_slide()

func _on_pickup_area_entered(area: Area2D) -> void:
	if picked_up:
		return
	var player := area.get_parent()
	if player == null or not player.is_in_group("player"):
		return
	match loot_type:
		LootType.COPPER_SHARD:
			GameState.add_copper_shard(value)
		LootType.SCALE_SHARD:
			GameState.scale_shard += value
			GameState.stats_changed.emit()
	picked_up = true
	sprite.visible = false
	pickup_area.set_deferred("monitoring", false)
	if pickup_sfx != null:
		pickup_sfx.play()
	get_tree().create_timer(picked_free_delay).timeout.connect(_on_destroy_timeout)
