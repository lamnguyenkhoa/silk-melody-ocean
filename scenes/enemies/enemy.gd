class_name Enemy
extends CharacterBody2D
## Port of Enemy.cs (plan 6.1). Base class for all enemies (and the P3 training dummy).
## Expected children (all optional except ContactArea for contact damage):
##   Visual (Node2D, holds the facing flip) > Sprite2D (+ AnimationPlayer),
##   ContactArea (Area2D, layer Enemy), LootPos (Marker2D),
##   HitParticles (CPUParticles2D), HitSfx (AudioStreamPlayer).
## AI subclasses override [method _ai_process]; it is skipped once the enemy is dead.

## Physics layer bits (project.godot layer names).
const LAYER_GROUND: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4
const LAYER_DEAD_ENEMY: int = 64

## Unity gravity 9.81 u/s^2 -> px/s^2 (Rigidbody2D.gravityScale multiplies this).
const UNITY_GRAVITY: float = 9.81 * 16.0
## Unity default 2D physics material: friction 0.4 (enemy and tile colliders both have no material,
## Box2D mixes sqrt(0.4 * 0.4) = 0.4). Ground friction decelerates a body by friction * g * gravity_scale
## per second while it rests on the floor (Box2D clamps the friction impulse to mu * normal impulse).
const GROUND_FRICTION: float = 0.4
## Unity: Enemy.StopMoving 0.25 s.
const STOP_MOVING_TIME: float = 0.25
## Unity: Enemy.iFrame 0.05 s.
const INVULNERABLE_TIME: float = 0.05
## Unity: Enemy.SpriteFlash 0.15 s.
const FLASH_TIME: float = 0.15
## Unity: Death() sprite colour r = g = b = 0.3.
const DEAD_TINT: float = 0.3
## Unity: Death() rb.gravityScale = 1, rb.drag = 1.
const DEAD_GRAVITY_SCALE: float = 1.0
const DEAD_DRAG: float = 1.0
## Unity: Death() explodeForce Random.Range(-5, 5) / Random.Range(5, 10) -> px/s (y flipped).
const LOOT_SPEED_X: float = 80.0
const LOOT_SPEED_Y_MIN: float = 80.0
const LOOT_SPEED_Y_MAX: float = 160.0
## Unity: FreezeTime() timeScale 0.2 for 0.2 s real time.
const DEATH_SLOW_SCALE: float = 0.2
const DEATH_SLOW_TIME: float = 0.2
## Unity: Destroy(gameObject, 10).
const CORPSE_LIFETIME: float = 10.0
## Unity: Enemy.fadeSpeed 2 and Destroy(gameObject, 0.5) (only if willBeDestroyed).
const FADE_SPEED: float = 2.0
const FADE_FREE_DELAY: float = 0.5
## Unity: Enemy.PlayDamagedSound Random.Range(0.8, 1) volume, Random.Range(0.7, 1.3) pitch.
const SFX_VOLUME_MIN: float = 0.8
const SFX_VOLUME_MAX: float = 1.0
const SFX_PITCH_MIN: float = 0.7
const SFX_PITCH_MAX: float = 1.3

const FLASH_SHADER_PATH := "res://scenes/vfx/flash.gdshader"
const HIT_SFX_PATH := "res://assets/sfx/hit_enemy.ogg"

# --- Stat (Unity: Enemy.maxHp, damage, knockbackAble, noContactDamage, enemyType) ---
@export var max_hp: int = 8
## Contact damage the enemy deals (the player currently always takes PlayerStats.contact_damage).
@export var damage: int = 1
@export var knockback_able: bool = true
@export var no_contact_damage: bool = false
## EnemyLore.EnemyType as int (Crawling 0, Dipsa 1, Crabber 3).
@export var enemy_type: int = 0
# --- On death ---
@export var drop_amount: int = 0
## Loot scene (CharacterBody2D with a `velocity`); null until P5.
@export var loot_scene: PackedScene
@export var will_be_destroyed: bool = false
# --- Physics (Rigidbody2D.gravityScale / linearDrag of the prefab) ---
@export var gravity_scale: float = 1.0
@export var drag: float = 0.0
## Unity default material friction (see GROUND_FRICTION); 0 disables ground friction.
@export var friction: float = GROUND_FRICTION

var current_hp: int = 0
var is_invulnerable: bool = false
## AI scripts must respect this flag (set for 0.25 s after a knockback, restartable).
var should_stop_moving: bool = false
var is_dead: bool = false

var _stop_timer: float = 0.0
var _invulnerable_timer: float = 0.0
var _flash_timer: float = 0.0
var _fade_alpha: float = 1.0
var _fade_free_timer: float = 0.0
var _flash_material: ShaderMaterial

@onready var visual: Node2D = get_node_or_null("Visual") as Node2D
@onready var sprite: Sprite2D = get_node_or_null("Visual/Sprite2D") as Sprite2D
@onready var anim: AnimationPlayer = get_node_or_null("Visual/AnimationPlayer") as AnimationPlayer
@onready var contact_area: Area2D = get_node_or_null("ContactArea") as Area2D
@onready var loot_pos: Marker2D = get_node_or_null("LootPos") as Marker2D
@onready var hit_particles: CPUParticles2D = get_node_or_null("HitParticles") as CPUParticles2D
@onready var hit_sfx: AudioStreamPlayer = get_node_or_null("HitSfx") as AudioStreamPlayer

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_GROUND
	if contact_area != null:
		contact_area.collision_layer = LAYER_ENEMY
		contact_area.collision_mask = 0
		contact_area.monitoring = false
	if sprite != null:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = load(FLASH_SHADER_PATH) as Shader
		sprite.material = _flash_material
	if hit_sfx != null and hit_sfx.stream == null:
		hit_sfx.stream = load(HIT_SFX_PATH) as AudioStream

## The player node (group "player"), or null.
func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

## Unity Physics2D.OverlapCircle(transform.position, radius, playerMask): true when the circle
## touches the player's body collider.
func player_in_circle(radius: float) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	q.shape = circle
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = LAYER_PLAYER
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()

## Override in AI scripts. Not called after death.
func _ai_process(_delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not is_dead:
		_ai_process(delta)
	velocity.y += UNITY_GRAVITY * gravity_scale * delta
	# Unity linear drag (plan 0.7)
	velocity *= 1.0 / (1.0 + drag * delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * UNITY_GRAVITY * gravity_scale * delta)
	move_and_slide()

func _process(delta: float) -> void:
	# Unity Update(): fade out dead enemies flagged willBeDestroyed.
	if is_dead and will_be_destroyed and sprite != null:
		if _fade_alpha > 0.0:
			_fade_alpha -= FADE_SPEED * delta
			sprite.modulate.a = maxf(_fade_alpha, 0.0)
		else:
			_fade_free_timer += delta
			if _fade_free_timer >= FADE_FREE_DELAY:
				queue_free()

func _tick_timers(delta: float) -> void:
	if _stop_timer > 0.0:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			should_stop_moving = false
	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta
		if _invulnerable_timer <= 0.0:
			is_invulnerable = false
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(0.0)

## Enemy.Damaged(amount, knockbackForce). [param knockback] is an impulse in px/s (mass 1).
func damaged(amount: int, knockback: Vector2) -> void:
	if knockback_able:
		_knockback(knockback)
	if not is_invulnerable:
		is_invulnerable = true
		_invulnerable_timer = INVULNERABLE_TIME
		_play_damaged_sound()
		_play_particles(knockback)
		_set_flash(1.0)
		_flash_timer = FLASH_TIME
		current_hp -= amount
		if current_hp <= 0:
			death()

func _knockback(knockback: Vector2) -> void:
	velocity = Vector2.ZERO
	velocity += knockback
	stop_moving()

## Enemy.StopMoving(): restartable 0.25 s.
func stop_moving() -> void:
	should_stop_moving = true
	_stop_timer = STOP_MOVING_TIME

func _set_flash(value: float) -> void:
	if _flash_material != null:
		_flash_material.set_shader_parameter("flash", value)

func _play_damaged_sound() -> void:
	if hit_sfx == null:
		return
	hit_sfx.volume_db = linear_to_db(randf_range(SFX_VOLUME_MIN, SFX_VOLUME_MAX))
	hit_sfx.pitch_scale = randf_range(SFX_PITCH_MIN, SFX_PITCH_MAX)
	hit_sfx.play()

func _play_particles(direction: Vector2) -> void:
	if hit_particles == null or direction == Vector2.ZERO:
		return
	hit_particles.direction = direction.normalized()
	hit_particles.restart()
	hit_particles.emitting = true

## Enemy.Death()
func death() -> void:
	if is_dead:
		return
	GameState.world.enemy_kill_count[enemy_type] = int(GameState.world.enemy_kill_count.get(enemy_type, 0)) + 1
	if contact_area != null:
		contact_area.set_deferred("monitorable", false)
	if sprite != null:
		sprite.modulate = Color(DEAD_TINT, DEAD_TINT, DEAD_TINT, sprite.modulate.a)
	# Unity flips the Sprite child (not the root), so a sprite offset keeps its position.
	if sprite != null:
		sprite.scale.y = -absf(sprite.scale.y)
	set_deferred("collision_layer", LAYER_DEAD_ENEMY)
	if anim != null:
		anim.stop()
	gravity_scale = DEAD_GRAVITY_SCALE
	drag = DEAD_DRAG
	is_dead = true
	_spawn_loot.call_deferred()
	Hitstop.slow(DEATH_SLOW_SCALE, DEATH_SLOW_TIME)
	get_tree().create_timer(CORPSE_LIFETIME, false).timeout.connect(queue_free)

## Loot hook: needs loot_scene (P5). Each piece gets a random upward burst.
func _spawn_loot() -> void:
	if loot_scene == null or drop_amount <= 0:
		return
	var host: Node = get_parent()
	if host == null:
		return
	var origin: Vector2 = loot_pos.global_position if loot_pos != null else global_position
	for i in drop_amount:
		var loot := loot_scene.instantiate() as Node2D
		loot.global_position = origin
		host.add_child(loot)
		loot.set("velocity", Vector2(
				randf_range(-LOOT_SPEED_X, LOOT_SPEED_X),
				-randf_range(LOOT_SPEED_Y_MIN, LOOT_SPEED_Y_MAX)))
