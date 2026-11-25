class_name Player
extends CharacterBody2D
## Port of Player.cs (plan section 5). P2 scope: movement, jump, coyote, ledge grab, dash,
## animation state, landing dust. Combat/skills (P3/P4) are NOT here yet, but their flags are
## declared so the control gate (section 5.1) is final.
##
## Flag/lock model like the original: independent bools + a control_lock counter.
## Unity space -> Godot space: 1 unit = 16 px, +y is down (see plan section 0).

enum State { IDLE, RUNNING, JUMPING, FALLING, HURT, DASHING, LEDGE }

const STATE_CLIPS: Dictionary = {
	State.IDLE: &"idle",
	State.RUNNING: &"run",
	State.JUMPING: &"jump",
	State.FALLING: &"fall",
	State.HURT: &"hurt",
	State.DASHING: &"dash",
	State.LEDGE: &"ledge_grab",
}

## Physics layer bits (project.godot layer names): Ground = layer 1.
const GROUND_MASK: int = 1
## Actions whose "just pressed / just released" edge is buffered from _input (plan 5.1).
const EDGE_ACTIONS: Array[StringName] = [&"jump", &"attack", &"dash", &"parry", &"silk_skill"]
## Unity: AnimationControl velocity threshold 0.1 u/s -> px/s.
const ANIM_VELOCITY_EPSILON: float = 0.1 * 16.0
## Unity: LandingDust airTime threshold (seconds) before dust + landing sound.
const LANDING_AIR_TIME: float = 0.2
## Unity: Jump()/HandleJump "+ 1f" so coyote can't give a double jump.
const COYOTE_BLOCK_EXTRA: float = 1.0
## Visual.scale.x sign for facing.
const FACE_RIGHT: float = 1.0
const FACE_LEFT: float = -1.0

@export var stats: PlayerStats

# --- Movement ---
var dash_count: int = 0
var jump_count: int = 0
var ver_input: float = 0.0
var hor_input: float = 0.0
var jump_timer: float = 0.0
var air_time: float = 0.0
var is_grounded: bool = false
var coyote_air_timer: float = 0.0
var gravity_on: bool = true
## Sitting on a chair / dead: skips physics integration (plan 5.1 step 6).
var is_kinematic: bool = false

# --- Ledge grab ---
var can_ledge_grab: bool = true
var green_box: bool = false
var red_box: bool = false

# --- Combat / lock flags (most are used from P3 on) ---
var control_lock: int = 0
var in_i_frame: bool = false
var attack_timer: float = 0.0
var parry_timer: float = 0.0
var is_paralyzed: bool = false
var is_slowed: bool = false
var in_attack: bool = false
var is_hurt: bool = false
var is_dashing: bool = false
var is_facing_left: bool = false
var is_jumping: bool = false
var is_ledge_grabbing: bool = false
var is_dead: bool = false
var in_silk_skill: bool = false
var is_parrying: bool = false
var resting: bool = false
var in_menu: bool = false
## Animator bools of the original (dashAttack / pogoAttack), cleared when a dash ends.
var anim_dash_attack: bool = false
var anim_pogo_attack: bool = false

var state: State = State.IDLE
## Name of a one-shot clip (attack, skills, ...) that overrides the state clip. P3+.
var anim_override: StringName = &""

var _dash_gen: int = 0
var _just_pressed: Dictionary = {}
var _just_released: Dictionary = {}
var _ground_query := PhysicsShapeQueryParameters2D.new()
var _ground_shape := RectangleShape2D.new()
var _probe_query := PhysicsShapeQueryParameters2D.new()
var _probe_shape := RectangleShape2D.new()

@onready var visual: Node2D = $Visual
@onready var body_shape: CollisionShape2D = $Body
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var dust: CPUParticles2D = $Visual/DustPE
@onready var dash_attack_pos: Marker2D = $Visual/DashAttackPos
@onready var pogo_attack_pos: Marker2D = $Visual/PogoAttackPos
@onready var ledge_green: Marker2D = $Visual/LedgeGreen
@onready var ledge_red: Marker2D = $Visual/LedgeRed
@onready var sfx: PlayerSfx = $Sfx

func _ready() -> void:
	if stats == null:
		stats = load("res://resources/player_stats_default.tres") as PlayerStats
	add_to_group("player")
	collision_layer = 2
	collision_mask = GROUND_MASK
	# Apply tuning from PlayerStats to the scene nodes (Unity prefab values).
	(body_shape.shape as RectangleShape2D).size = stats.collider_size
	body_shape.position = stats.collider_offset
	dash_attack_pos.position = stats.dash_attack_pos
	pogo_attack_pos.position = stats.pogo_attack_pos
	ledge_green.position = stats.ledge_green_offset
	ledge_red.position = stats.ledge_red_offset
	dust.position = stats.dust_offset
	_ground_shape.size = stats.ground_check_size
	_ground_query.shape = _ground_shape
	_ground_query.collision_mask = GROUND_MASK
	_probe_shape.size = stats.ledge_probe_size
	_probe_query.shape = _probe_shape
	_probe_query.collision_mask = GROUND_MASK
	dash_count = GameState.max_dash
	jump_count = GameState.extra_jump
	anim.play(STATE_CLIPS[State.IDLE] as StringName)

## Buffers press/release edges so a tap between two physics ticks is never lost
## (WasPressedThisFrame / WasReleasedThisFrame equivalent).
func _input(event: InputEvent) -> void:
	for action: StringName in EDGE_ACTIONS:
		if event.is_action_pressed(action, false):
			_just_pressed[action] = true
		if event.is_action_released(action):
			_just_released[action] = true

func _was_pressed(action: StringName) -> bool:
	return _just_pressed.has(action) or Input.is_action_just_pressed(action)

func _was_released(action: StringName) -> bool:
	return _just_released.has(action) or Input.is_action_just_released(action)

# --- Per-frame order (plan 5.1) ---

func _physics_process(delta: float) -> void:
	_check_grounded()

	if not in_attack:
		attack_timer += delta
	if not is_parrying:
		parry_timer += delta

	if _can_control():
		_handle_movement()
		_handle_jump(delta)
		# P3: _handle_attack(), _handle_parry()
		_handle_dash()
		if can_ledge_grab:
			_handle_ledge_grab()
		_handle_coyote_time(delta)
		# P4: _handle_silk_skill()

	_animation_control()
	_landing_dust(delta)

	if not is_kinematic:
		if gravity_on:
			velocity.y += stats.gravity * delta
		# Unity linear drag (plan 0.7): v *= 1 / (1 + drag * dt)
		velocity *= 1.0 / (1.0 + stats.linear_drag * delta)
		move_and_slide()

	_just_pressed.clear()
	_just_released.clear()

func _can_control() -> bool:
	return not resting and control_lock == 0 and not is_dashing and not is_paralyzed \
			and not in_silk_skill and not is_parrying and not in_menu

func _check_grounded() -> void:
	# Unity: OverlapBox at groundCheck (not is_on_floor), so it stays true while gravity is off.
	_ground_query.transform = Transform2D(0.0, global_position + stats.ground_check_offset)
	is_grounded = _query_ground(_ground_query)

func _query_ground(query: PhysicsShapeQueryParameters2D) -> bool:
	var space := get_world_2d().direct_space_state
	return not space.intersect_shape(query, 1).is_empty()

# --- 5.2 Movement ---

func _handle_movement() -> void:
	var direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	ver_input = -direction.y # Godot up is -y; keep Unity convention (positive = up)
	hor_input = direction.x

	if hor_input < 0.0 and not in_attack:
		is_facing_left = true
		_flip()
	elif hor_input > 0.0 and not in_attack:
		is_facing_left = false
		_flip()
	var speed_modifier: float = stats.slowed_speed_modifier if is_slowed else 1.0
	velocity.x = hor_input * GameState.move_speed * speed_modifier

func _flip() -> void:
	var want: float = FACE_LEFT if is_facing_left else FACE_RIGHT
	if visual.scale.x != want:
		visual.scale.x = want
		if is_grounded:
			_play_dust()

## +1 right, -1 left.
func facing() -> int:
	return -1 if is_facing_left else 1

# --- 5.3 Jump ---

func _handle_jump(delta: float) -> void:
	if _was_pressed(&"jump"):
		if is_grounded or is_ledge_grabbing or coyote_air_timer <= stats.coyote_time:
			_jump()
		elif jump_count > 0:
			_jump()
			jump_count -= 1
	if Input.is_action_pressed(&"jump") and is_jumping:
		if jump_timer > 0.0:
			velocity.y = -GameState.jump_force
			jump_timer -= delta
		else:
			is_jumping = false
	if _was_released(&"jump") and is_jumping:
		# Hard cut on release (Unity behaviour).
		jump_timer = 0.0
		is_jumping = false
		velocity.y = 0.0
		coyote_air_timer = stats.coyote_time + COYOTE_BLOCK_EXTRA

func _jump() -> void:
	jump_timer = stats.max_jump_time
	is_jumping = true
	velocity.y = -GameState.jump_force
	coyote_air_timer = stats.coyote_time + COYOTE_BLOCK_EXTRA # prevent coyote double jump
	sfx.play_sound(PlayerSfx.Sound.JUMP)
	_play_dust()

# --- 5.4 Coyote ---

func _handle_coyote_time(delta: float) -> void:
	if not is_grounded and not is_ledge_grabbing:
		coyote_air_timer += delta
	else:
		coyote_air_timer = 0.0

# --- 5.5 Ledge grab ---

func _handle_ledge_grab() -> void:
	if is_dashing:
		return
	# Probes live under Visual, so they mirror with facing automatically.
	green_box = _probe_overlaps_ground(ledge_green.global_position)
	red_box = _probe_overlaps_ground(ledge_red.global_position)

	is_ledge_grabbing = green_box and not red_box and not is_jumping and not is_grounded

	if is_ledge_grabbing:
		velocity = Vector2.ZERO
		gravity_on = false
		dash_count = GameState.max_dash
		jump_count = GameState.extra_jump
	else:
		# Unity quirk kept: gravity is restored every controllable frame here.
		gravity_on = true

func _probe_overlaps_ground(center: Vector2) -> bool:
	_probe_query.transform = Transform2D(0.0, center)
	return _query_ground(_probe_query)

# --- 5.6 Dash ---

func _handle_dash() -> void:
	if _was_pressed(&"dash") and not is_dashing and dash_count > 0:
		dash_count -= 1
		_play_dust()
		_do_dash(false, Vector2(facing(), 0.0))

## Port of the Dash coroutine. Starting a new dash (or [method cancel_dash]) invalidates
## the previous one via the generation counter. [param dir] is NOT normalised.
func _do_dash(also_attack: bool, dir: Vector2) -> void:
	_dash_gen += 1
	var my_gen: int = _dash_gen
	sfx.play_sound(PlayerSfx.Sound.DASH)
	is_dashing = true
	if also_attack:
		in_attack = true
	gravity_on = false
	velocity = Vector2.ZERO
	velocity += dir * GameState.dash_force
	# process_in_physics = true so the wait is counted in physics ticks (deterministic).
	await get_tree().create_timer(GameState.dash_time, true, true).timeout
	if my_gen != _dash_gen:
		return
	is_dashing = false
	gravity_on = true
	if also_attack:
		in_attack = false
		anim_dash_attack = false
		anim_pogo_attack = false

## StopCoroutine(dashCoroutine): the pending wait of the running dash becomes a no-op.
func cancel_dash() -> void:
	_dash_gen += 1

# --- 5.14 Animation state ---

func _animation_control() -> void:
	if is_dead or is_hurt or is_paralyzed:
		state = State.HURT
	elif is_dashing:
		state = State.DASHING
	elif velocity.y < -ANIM_VELOCITY_EPSILON:
		state = State.JUMPING
	elif velocity.y > ANIM_VELOCITY_EPSILON:
		state = State.FALLING
	elif absf(velocity.x) > ANIM_VELOCITY_EPSILON:
		state = State.RUNNING
	elif is_ledge_grabbing:
		state = State.LEDGE
	else:
		state = State.IDLE

	if anim_override == &"":
		var clip: StringName = STATE_CLIPS[state] as StringName
		if anim.current_animation != clip:
			anim.play(clip)

func get_state_name() -> String:
	return State.keys()[state] as String

# --- 5.1 step 5: landing dust / refill ---

func _landing_dust(delta: float) -> void:
	if not is_grounded:
		air_time += delta
	else:
		if air_time > LANDING_AIR_TIME:
			_play_dust()
			sfx.play_sound(PlayerSfx.Sound.LANDING)
		air_time = 0.0
		dash_count = GameState.max_dash
		jump_count = GameState.extra_jump

func _play_dust() -> void:
	dust.restart()
	dust.emitting = true
