class_name Crabber
extends Enemy
## Port of CrabberAI.cs + RbPathfindAI.cs (plan 6.5): ground charger. No A* pathfinding: it walks
## horizontally toward the player. Sprite faces LEFT by default.

## Unity: CrabberAI.timeBetweenAttack 3 s.
@export var time_between_attack: float = 3.0
## Unity: CrabberAI.detectionRadius 6 u / attackRadius 3 u.
@export var detection_radius: float = 96.0
@export var attack_radius: float = 48.0
## Unity: RbPathfindAI.speed 400 * fixedDeltaTime 0.02 = 8 N, mass 1 -> 8 u/s^2 (ground friction
## then limits the walking speed to ~4 u/s, see Enemy.GROUND_FRICTION).
@export var move_acceleration: float = 128.0
## Unity: AddForce(direction * dashAttackForce 300) for one 0.02 s step -> dv = 6 u/s.
@export var dash_attack_speed: float = 96.0

var alerted: bool = false
var in_attack: bool = false
var attack_timer: float = 0.0

func _ready() -> void:
	super._ready()
	if anim != null:
		anim.animation_finished.connect(_on_anim_finished)

func _ai_process(delta: float) -> void:
	var player := get_player()
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	if alerted:
		_steer(to_player, delta)
		if in_attack:
			return
		should_stop_moving = to_player.length() <= attack_radius
		attack_timer += delta
		if attack_timer >= time_between_attack and to_player.length() <= attack_radius:
			if anim != null:
				anim.play(&"attack")
			attack_timer = 0.0
	else:
		attack_timer = 0.0
		if player_in_circle(detection_radius):
			alerted = true

## RbPathfindAI.FixedUpdate (canFly = false): horizontal force toward the target unless
## shouldStopMoving; the sprite flips toward the target regardless.
func _steer(to_player: Vector2, delta: float) -> void:
	var dir_x: float = signf(to_player.x)
	if dir_x == 0.0:
		return
	if not should_stop_moving:
		velocity.x += dir_x * move_acceleration * delta
	if visual != null:
		visual.scale.x = -1.0 if dir_x > 0.0 else 1.0

# --- Animation events (Attack.anim) ---

func begin_attack() -> void:
	in_attack = true
	should_stop_moving = true

func end_attack() -> void:
	in_attack = false
	should_stop_moving = false

func dash_forward() -> void:
	if is_dead:
		return
	var player := get_player()
	var dir_x: float = 1.0 if visual != null and visual.scale.x < 0.0 else -1.0
	if player != null and player.global_position.x != global_position.x:
		dir_x = signf(player.global_position.x - global_position.x)
	velocity.x += dir_x * dash_attack_speed

func _on_anim_finished(clip: StringName) -> void:
	if clip == &"attack" and not is_dead:
		anim.play(&"idle")
