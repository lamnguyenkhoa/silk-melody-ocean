class_name Dipsa
extends Enemy
## Port of DipsaAI.cs + RbPathfindAI.cs (plan 6.3): flying shooter. No A* pathfinding: it steers
## along the straight line to the player. Sprite faces LEFT by default.

## Unity: DipsaAI.timeBetweenAttack 3 s.
@export var time_between_attack: float = 3.0
## Unity: DipsaAI.bulletSpeed 5 u/s.
@export var bullet_speed: float = 80.0
## Unity: DipsaAI.detectionRadius 10 u.
@export var detection_radius: float = 160.0
## Unity: RbPathfindAI.speed 250 * fixedDeltaTime 0.02 = 5 N, mass 1 -> 5 u/s^2.
@export var move_acceleration: float = 80.0
@export var bullet_scene: PackedScene

## Unity: flips when force.x >= 0.01 with force = dir * 5 N -> |dir.x| >= 0.002.
const FLIP_DEADZONE: float = 0.002

var alerted: bool = false
var attack_timer: float = 0.0

@onready var shoot_pos: Marker2D = $ShootPos

func _ai_process(delta: float) -> void:
	var player := get_player()
	if player == null:
		return
	if alerted:
		var to_player: Vector2 = player.global_position - global_position
		var dist: float = to_player.length()
		should_stop_moving = dist <= detection_radius
		attack_timer += delta
		if attack_timer >= time_between_attack and dist <= detection_radius:
			_attack(to_player)
			attack_timer = 0.0
		_steer(to_player, delta)
	else:
		attack_timer = 0.0
		if player_in_circle(detection_radius):
			alerted = true

## RbPathfindAI.FixedUpdate: AddForce toward the target unless shouldStopMoving, flip toward it.
func _steer(to_player: Vector2, delta: float) -> void:
	if to_player == Vector2.ZERO:
		return
	var dir: Vector2 = to_player.normalized()
	if not should_stop_moving:
		velocity += dir * move_acceleration * delta
	if visual != null:
		if dir.x >= FLIP_DEADZONE:
			visual.scale.x = -1.0
		elif dir.x <= -FLIP_DEADZONE:
			visual.scale.x = 1.0

func _attack(to_player: Vector2) -> void:
	stop_moving()
	if bullet_scene == null:
		return
	var bullet := bullet_scene.instantiate() as Projectile
	bullet.global_position = shoot_pos.global_position
	bullet.velocity = to_player.normalized() * bullet_speed
	get_parent().add_child(bullet)
