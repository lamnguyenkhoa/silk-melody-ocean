class_name Player
extends CharacterBody2D
## Port of Player.cs (plan section 5). P2: movement, jump, coyote, ledge grab, dash, animation
## state, landing dust. P3: attack / pogo / slashes, parry + riposte, damage pipeline, i-frames,
## stun, contact damage, status effects, death. P4: silk skills (heal, gossamer, silk burst).
##
## Flag/lock model like the original: independent bools + a control_lock counter.
## Unity space -> Godot space: 1 unit = 16 px, +y is down (see plan section 0).

enum State { IDLE, RUNNING, JUMPING, FALLING, HURT, DASHING, LEDGE }
## Unity: Player.StatusEffect.
enum StatusEffect { NONE, PARALYZED, SLOWED, DRAINED }

## Emitted at the start of _death() (P6 RoomLoader / tests listen).
signal died

const STATE_CLIPS: Dictionary = {
	State.IDLE: &"idle",
	State.RUNNING: &"run",
	State.JUMPING: &"jump",
	State.FALLING: &"fall",
	State.HURT: &"hurt",
	State.DASHING: &"dash",
	State.LEDGE: &"ledge_grab",
}

const PARRY_CLIPS: Dictionary = {
	1: &"parry",
	2: &"parry_received",
	3: &"parry_riposte",
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
## Physics layer bits (project.godot layer names).
const LAYER_ENEMY: int = 4
const LAYER_ENEMY_ATTACK: int = 16
const LAYER_PLAYER_TRIGGER: int = 128
## Unity: LevelLoader.transitionTime fallback if RoomLoader is not available.
const DEFAULT_TRANSITION_TIME: float = 1.0
const SLASH_SCENE_PATH := "res://scenes/player/player_slash.tscn"
const SLASH_SPARK_SCENE_PATH := "res://scenes/vfx/slash_spark.tscn"
const HURT_SPARK_SCENE_PATH := "res://scenes/vfx/hurt_spark.tscn"
const HURT_PE_SCENE_PATH := "res://scenes/vfx/hurt_pe.tscn"
const FLASH_SHADER_PATH := "res://scenes/vfx/flash.gdshader"
const SILK_BIND_SCENE_PATH := "res://scenes/vfx/silk_bind.tscn"
const GOSSAMER_SCENE_PATH := "res://scenes/player/gossamer.tscn"
const SILK_BURST_SCENE_PATH := "res://scenes/player/silk_burst.tscn"
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
## Name of a one-shot clip (attack, skills, ...) that overrides the state clip.
var anim_override: StringName = &""
## Unity Animator int parryState: 0 none, 1 Parry, 2 ParryReceived, 3 ParryRipose.
var parry_state: int = 0
## Active Gossamer / SilkBurst instances (P4); freed when the player is hit.
var gossamer_instance: Node = null
var silk_burst_instance: Node = null

var _dash_gen: int = 0
var _parry_gen: int = 0
var _riposte_gen: int = 0
var _iframe_gen: int = 0
var _stun_gen: int = 0
var _stun_active: bool = false
var _flash_gen: int = 0
var _paralyze_gen: int = 0
var _slow_gen: int = 0
var _contact_recheck: int = 0
var _flash_material: ShaderMaterial
var _slash_scene: PackedScene
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
@onready var sprite: Sprite2D = $Visual/Sprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var player_trigger: Area2D = $PlayerTrigger

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
	# Hurtbox: Area2D, no layer, mask Enemy + EnemyAttack (replaces Unity's collision callbacks).
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = LAYER_ENEMY | LAYER_ENEMY_ATTACK
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	# PlayerTrigger: layer 8 so pickups / interactables can find the player.
	player_trigger.collision_layer = LAYER_PLAYER_TRIGGER
	player_trigger.collision_mask = 0
	player_trigger.monitoring = false
	for shape_owner: Area2D in [hurtbox, player_trigger]:
		var shape_node := shape_owner.get_node("Shape") as CollisionShape2D
		(shape_node.shape as RectangleShape2D).size = stats.collider_size
		shape_node.position = stats.collider_offset
	# Animation events must fire in physics time, immediately (exact Unity timing, hit-stop pauses them).
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	anim.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	anim.animation_finished.connect(_on_animation_finished)
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = load(FLASH_SHADER_PATH) as Shader
	sprite.material = _flash_material
	_slash_scene = load(SLASH_SCENE_PATH) as PackedScene
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
		_handle_attack()
		_handle_parry()
		_handle_dash()
		if can_ledge_grab:
			_handle_ledge_grab()
		_handle_coyote_time(delta)
		_handle_silk_skill()

	_animation_control()
	_landing_dust(delta)
	_recheck_contacts(delta)

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
	await get_tree().create_timer(GameState.dash_time, false, true).timeout
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

# --- 5.13 Silk skills ---

## HandleSilkSkill(): the cost is paid at press; the clip's method-call tracks do the rest.
## Unity if/else-if chain kept: holding Up/Down without enough silk for that skill falls through
## to the next branch (in practice only Heal can then trigger, which needs 8 silk).
func _handle_silk_skill() -> void:
	if not _was_pressed(&"silk_skill") or in_attack:
		return
	if ver_input >= stats.ver_input_threshold and GameState.current_silk >= stats.gossamer_cost:
		GameState.add_silk(-stats.gossamer_cost)
		_play_one_shot(&"gossamer")
	elif ver_input <= -stats.ver_input_threshold and GameState.current_silk >= stats.silk_burst_cost:
		GameState.add_silk(-stats.silk_burst_cost)
		_play_one_shot(&"silk_burst")
	elif GameState.current_silk >= stats.heal_cost and GameState.current_hp < GameState.max_hp:
		GameState.add_silk(-stats.heal_cost)
		_play_one_shot(&"heal")

## Shared by BeginHeal / BeginGossamer / BeginSilkBurst: lock input, freeze in place.
func _begin_silk_skill_lock() -> void:
	in_silk_skill = true
	velocity = Vector2.ZERO
	gravity_on = false

## Animation event (heal clip @0.0).
func begin_heal() -> void:
	sfx.play_sound(PlayerSfx.Sound.SILKBIND)
	_begin_silk_skill_lock()
	# Unity: child of the (flipped) player transform; here Visual carries the flip.
	var vfx := (load(SILK_BIND_SCENE_PATH) as PackedScene).instantiate() as Node2D
	vfx.position = stats.skill_vfx_pos
	visual.add_child(vfx)

## Animation event (heal clip @0.5833).
func actual_heal() -> void:
	heal(GameState.silk_heal)

## Animation event (heal @1.0, gossamer @1.0 "EndGossamer", silk_burst @0.9667 "EndSilkBurst").
func end_heal() -> void:
	in_silk_skill = false
	gravity_on = true

## Animation event (gossamer clip @0.0).
func begin_gossamer() -> void:
	_begin_silk_skill_lock()
	var instance := (load(GOSSAMER_SCENE_PATH) as PackedScene).instantiate() as Gossamer
	instance.position = stats.skill_vfx_pos # set before add_child: the circle centre is read in _ready
	instance.player_pos = global_position
	visual.add_child(instance)
	gossamer_instance = instance

## Animation event (silk_burst clip @0.0).
func begin_silk_burst() -> void:
	_begin_silk_skill_lock()

## Animation event (silk_burst clip @0.1667).
func throw_silk_burst() -> void:
	var instance := (load(SILK_BURST_SCENE_PATH) as PackedScene).instantiate() as SilkBurst
	instance.position = stats.silk_burst_pos
	instance.player_pos = global_position
	visual.add_child(instance)
	silk_burst_instance = instance

## Animation event (silk_burst clip @0.8333): pushes the player back, away from the facing side.
func catch_silk_burst_recoil() -> void:
	velocity += Vector2(stats.silk_burst_recoil.x * facing(), stats.silk_burst_recoil.y)

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

	# One-shot clips (attack, skills) win; then the parry states, then the dash-attack / pogo
	# flags (Animator bools), then the looping state clip.
	var clip: StringName = &""
	if anim_override != &"":
		return
	if parry_state != 0:
		clip = PARRY_CLIPS[parry_state] as StringName
	elif anim_pogo_attack:
		clip = &"pogo_attack"
	elif anim_dash_attack:
		clip = &"dash_attack"
	else:
		clip = STATE_CLIPS[state] as StringName
	if anim.current_animation != clip:
		anim.play(clip)

func _on_animation_finished(clip_name: StringName) -> void:
	if clip_name == anim_override:
		anim_override = &""

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

# --- 5.7 Attack ---

func _handle_attack() -> void:
	if _was_pressed(&"attack") and attack_timer > GameState.attack_cooldown and not in_attack:
		if ver_input >= stats.ver_input_threshold:
			_play_one_shot(&"attack_up")
			_attack_deal_damage(true)
		elif ver_input <= -stats.ver_input_threshold and not is_grounded:
			_pogo_attack()
		else:
			_play_one_shot(&"attack")
			_attack_deal_damage(false)
		sfx.play_sound(PlayerSfx.Sound.ATTACK)
		attack_timer = 0.0

## Plays a one-shot clip that overrides the state clip until it finishes (or is cancelled).
func _play_one_shot(clip: StringName) -> void:
	anim_override = clip
	anim.play(clip)

## Animation events (attack / attack_up clips, hurt clip).
func begin_attack_anim() -> void:
	in_attack = true

func end_attack_anim() -> void:
	in_attack = false

## Creates a slash of [param kind] under Visual (so it mirrors with facing) at local [param pos].
func _spawn_slash(kind: PlayerSlash.Kind, pos: Vector2, rotation_deg: float = 0.0) -> PlayerSlash:
	var slash := _slash_scene.instantiate() as PlayerSlash
	slash.setup(self, kind)
	visual.add_child(slash)
	slash.position = pos
	slash.rotation_degrees = rotation_deg
	return slash

func _attack_deal_damage(is_up_attack: bool) -> void:
	if is_up_attack:
		_spawn_slash(PlayerSlash.Kind.SLASH, stats.slash_up_pos, stats.slash_up_rotation_deg)
	else:
		_spawn_slash(PlayerSlash.Kind.SLASH, stats.slash_forward_pos)

# --- 5.8 Pogo ---

func _pogo_attack() -> void:
	_play_dust()
	# Unity (+-1 x, -1 y) -> Godot (+-1 x, +1 y): down-forward diagonal, NOT normalised.
	_do_dash(true, Vector2(facing(), 1.0))
	anim_pogo_attack = true
	_spawn_slash(PlayerSlash.Kind.POGO_SLASH, pogo_attack_pos.position)

## PlayerSlash.EnemyImpactEffect -> AttackRecoil(canResetDash).
func attack_recoil(reset_dash: bool) -> void:
	cancel_dash()
	is_dashing = false
	gravity_on = true
	in_attack = false
	anim_dash_attack = false
	anim_pogo_attack = false
	velocity = Vector2.ZERO
	velocity += stats.dash_recoil
	if reset_dash:
		dash_count = GameState.max_dash
		jump_count = GameState.extra_jump

## DashSlash / PogoSlash touched Ground: like recoil without the bounce or the refill.
func dash_attack_touch_ground() -> void:
	cancel_dash()
	is_dashing = false
	gravity_on = true
	in_attack = false
	anim_dash_attack = false
	anim_pogo_attack = false
	velocity = Vector2.ZERO

# --- 5.10 Parry & riposte ---

func _handle_parry() -> void:
	if _was_pressed(&"parry") and not in_attack and is_grounded:
		if parry_timer >= GameState.parry_cooldown:
			parry_timer = 0.0
			velocity = Vector2.ZERO
			_parrying()

func _parrying() -> void:
	_parry_gen += 1
	var my_gen: int = _parry_gen
	is_parrying = true
	parry_state = 1
	await _wait(GameState.parry_window)
	if my_gen != _parry_gen:
		return
	parry_state = 0
	is_parrying = false

func _parry_riposte() -> void:
	_riposte_gen += 1
	var my_gen: int = _riposte_gen
	# Get hit -> freeze time.
	parry_state = 2
	sfx.play_sound(PlayerSfx.Sound.PARRY)
	await Hitstop.freeze(stats.parry_freeze_time)
	if my_gen != _riposte_gen:
		return
	# I-frames (hurtbox off, no alpha change).
	_begin_i_frames(false)
	# Dash forward and attack.
	sfx.play_sound(PlayerSfx.Sound.ATTACK)
	parry_state = 3
	var dash_slash: PlayerSlash = _spawn_slash(PlayerSlash.Kind.DASH_SLASH, dash_attack_pos.position)
	dash_slash.has_recoil = false
	dash_slash.piercing = true
	_play_dust()
	is_dashing = true
	in_attack = true
	gravity_on = false
	velocity = Vector2.ZERO
	velocity += Vector2(facing() * GameState.dash_force * stats.riposte_dash_multiplier, 0.0)
	# Finish dash and attack.
	await _wait(GameState.dash_time)
	if my_gen != _riposte_gen:
		return
	is_dashing = false
	in_attack = false
	is_parrying = false
	gravity_on = true
	parry_state = 0
	# Bonus i-frame time.
	await _wait(stats.riposte_i_frame_tail)
	if my_gen != _riposte_gen:
		return
	_end_i_frames()
	# Reset parry cooldown.
	parry_timer = GameState.parry_cooldown

# --- 5.11 Taking damage ---

## Damaged(amount, knockbackDir). [param amount] must be positive.
func damaged(amount: int, knockback_dir: Vector2) -> void:
	var original_amount: int = amount
	if in_i_frame or is_dead:
		return
	if is_parrying:
		_parry_gen += 1 # StopCoroutine(parryCoroutine)
		_parry_riposte()
		return

	# Disable all active silk skills.
	if is_instance_valid(gossamer_instance):
		gossamer_instance.queue_free()
	if is_instance_valid(silk_burst_instance):
		silk_burst_instance.queue_free()

	# Damage calculation: lifeblood absorbs first.
	sfx.play_sound(PlayerSfx.Sound.DAMAGED)
	if amount <= GameState.lifeblood_hp:
		GameState.lifeblood_hp -= amount
		amount = 0
	else:
		amount -= GameState.lifeblood_hp
		GameState.lifeblood_hp = 0
	GameState.current_hp = clampi(GameState.current_hp - amount, 0, GameState.max_hp)
	GameState.stats_changed.emit()

	# Damaged after-effects: reset states and cancel routines whose events could fire later.
	gravity_on = true
	cancel_dash()
	_parry_gen += 1
	_riposte_gen += 1
	is_dashing = false
	in_attack = false
	is_paralyzed = false
	in_silk_skill = false
	is_parrying = false
	parry_state = 0
	anim_dash_attack = false
	anim_pogo_attack = false
	_flash_gen += 1
	_set_flash(0.0)
	anim.stop() # one-shot clip events (end_heal, end_attack_anim, ...) must not fire later
	anim_override = &""

	var vignette := get_tree().get_first_node_in_group("hurt_vignette")
	if vignette != null:
		vignette.call("pulse")
	var cam := get_viewport().get_camera_2d() as GameCamera
	if cam != null:
		cam.shake(stats.damage_shake_intensity, stats.damage_shake_time, true)
	_spawn_hurt_effects()

	if GameState.current_hp <= 0:
		_death()
	else:
		# Order matters: _stunned() zeroes velocity BEFORE the knockback impulse is added.
		Hitstop.freeze(stats.hurt_freeze_per_damage * original_amount)
		_i_frame()
		_stunned()
		velocity += knockback_dir * stats.hurt_knockback + stats.hurt_knockback_up

func _spawn_hurt_effects() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var spark := (load(HURT_SPARK_SCENE_PATH) as PackedScene).instantiate() as Node2D
	spark.global_position = global_position
	spark.rotation = deg_to_rad(randf_range(-stats.hurt_spark_rotation_deg, stats.hurt_spark_rotation_deg))
	host.add_child(spark)
	var pe := (load(HURT_PE_SCENE_PATH) as PackedScene).instantiate() as CPUParticles2D
	pe.global_position = global_position
	host.add_child(pe)
	pe.emitting = true

func _i_frame() -> void:
	_iframe_gen += 1
	var my_gen: int = _iframe_gen
	_begin_i_frames(true)
	await _wait(GameState.i_frame_time)
	if my_gen != _iframe_gen:
		return
	_end_i_frames()

## Hurtbox monitoring off replaces Unity's Physics2D.IgnoreLayerCollision(Player, Enemy/EnemyAttack).
func _begin_i_frames(fade: bool) -> void:
	in_i_frame = true
	hurtbox.set_deferred("monitoring", false)
	if fade:
		sprite.modulate.a = stats.i_frame_alpha

func _end_i_frames() -> void:
	in_i_frame = false
	hurtbox.set_deferred("monitoring", true)
	sprite.modulate.a = 1.0
	# Standing inside an enemy must hurt again: re-check overlaps shortly after monitoring is back.
	_contact_recheck = stats.contact_recheck_ticks

func _stunned() -> void:
	_stun_gen += 1
	var my_gen: int = _stun_gen
	_stun_active = true
	is_hurt = true
	control_lock += 1
	velocity = Vector2.ZERO
	await _wait(GameState.stun_time)
	if my_gen != _stun_gen:
		return
	_end_stun()

func _end_stun() -> void:
	if _stun_active:
		_stun_active = false
		control_lock -= 1
		is_hurt = false

func _death() -> void:
	is_dead = true
	control_lock += 1
	is_kinematic = true
	velocity = Vector2.ZERO
	died.emit()
	var transition_time: float = DEFAULT_TRANSITION_TIME
	var loader: Node = get_node_or_null("/root/RoomLoader")
	if loader != null:
		if loader.has_method("respawn"):
			loader.call("respawn")
		var t: Variant = loader.get("transition_time")
		if t != null:
			transition_time = float(t)
	await _wait(transition_time)
	is_dead = false
	GameState.current_hp = GameState.max_hp
	GameState.stats_changed.emit()
	control_lock -= 1

# --- Contact damage ---

func _on_hurtbox_area_entered(area: Area2D) -> void:
	var enemy := area.get_parent() as Enemy
	if enemy == null or enemy.no_contact_damage or enemy.is_dead:
		return
	var knockback_dir: Vector2 = (global_position - enemy.global_position).normalized()
	damaged(stats.contact_damage, knockback_dir)

func _recheck_contacts(_delta: float) -> void:
	if _contact_recheck <= 0:
		return
	_contact_recheck -= 1
	if _contact_recheck == 0 and not in_i_frame and not is_dead and hurtbox.monitoring:
		for area: Area2D in hurtbox.get_overlapping_areas():
			_on_hurtbox_area_entered(area)

# --- 5.12 Status effects ---

func inflicted_status_effect(status: StatusEffect) -> void:
	if is_parrying:
		return
	match status:
		StatusEffect.PARALYZED:
			_got_paralyzed()
		StatusEffect.SLOWED:
			_got_slowed()
		StatusEffect.DRAINED:
			GameState.add_silk(-stats.drained_silk)

func _got_paralyzed() -> void:
	_paralyze_gen += 1
	var my_gen: int = _paralyze_gen
	velocity = Vector2.ZERO
	is_paralyzed = true
	await _wait(stats.paralyzed_time)
	if my_gen == _paralyze_gen:
		is_paralyzed = false

func _got_slowed() -> void:
	_slow_gen += 1
	var my_gen: int = _slow_gen
	is_slowed = true
	await _wait(stats.slowed_time)
	if my_gen == _slow_gen:
		is_slowed = false

# --- Misc (5.15) ---

func heal(amount: int) -> void:
	GameState.current_hp = mini(GameState.current_hp + amount, GameState.max_hp)
	GameState.stats_changed.emit()
	flash_white()

## RestChairRecovery(): StopAllCoroutines + full hp. Unlike Unity (where StopAllCoroutines can
## leave inIFrame / the stun control lock stuck), the cancelled routines are cleaned up properly.
func rest_chair_recovery() -> void:
	cancel_dash()
	_parry_gen += 1
	_riposte_gen += 1
	_iframe_gen += 1
	_stun_gen += 1
	_flash_gen += 1
	_paralyze_gen += 1
	_slow_gen += 1
	_end_stun()
	if in_i_frame:
		_end_i_frames()
	is_parrying = false
	is_paralyzed = false
	is_slowed = false
	parry_state = 0
	_set_flash(0.0)
	GameState.current_hp = GameState.max_hp
	GameState.stats_changed.emit()
	is_dashing = false
	in_attack = false
	anim_dash_attack = false
	anim_pogo_attack = false

## RestChair.GetOnChair: invulnerable to enemies while sitting (Unity: IgnoreLayerCollision(Player,
## Enemy / EnemyAttack)). Implemented as an endless i-frame (hurtbox off, no blink) so bullets, which
## skip the player while in_i_frame, pass through too.
func begin_rest_invulnerability() -> void:
	_iframe_gen += 1
	_begin_i_frames(false)

## RestChair.GetOffChair: collisions back on (re-checks overlapping enemies, like the i-frame end).
func end_rest_invulnerability() -> void:
	_iframe_gen += 1
	_end_i_frames()

## FlashWhite(): sprite shows the white flash material for [param duration].
func flash_white(duration: float = -1.0) -> void:
	_flash_gen += 1
	var my_gen: int = _flash_gen
	_set_flash(1.0)
	await _wait(stats.flash_white_time if duration < 0.0 else duration)
	if my_gen == _flash_gen:
		_set_flash(0.0)

func _set_flash(value: float) -> void:
	_flash_material.set_shader_parameter("flash", value)

## WaitForSeconds equivalent: counted in physics ticks, scaled by Engine.time_scale.
func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, false, true).timeout
