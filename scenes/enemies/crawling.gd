class_name Crawling
extends Enemy
## Port of CrawlingAI.cs (plan 6.2). Patrols a platform, turning around at ledges and walls.
## Sprite faces LEFT by default; Visual.scale.x = -1 faces right.

## Unity: CrawlingAI.speed 3 u/s.
@export var speed: float = 48.0
## Unity: CrawlingAI.isMovingRight (prefab false).
@export var is_moving_right: bool = false
## Unity: CheckObstaclePos local x -0.773 u (mirrored with the facing).
@export var check_obstacle_distance: float = 12.368
## Unity: Raycast length 1 u.
@export var fall_check_length: float = 16.0
## Unity: OverlapCircle radius 0.1 u.
@export var wall_check_radius: float = 1.6
## Unity: lerp factor 0.1 per FixedUpdate step of 0.02 s.
@export var lerp_weight: float = 0.1
@export var lerp_step: float = 0.02
## Unity: notWallMask excludes everything but Ground and DeadEnemy (among the ported layers).
@export_flags_2d_physics var obstacle_mask: int = LAYER_GROUND | LAYER_DEAD_ENEMY

var near_wall: bool = false
var near_fall: bool = false
var stabilized: bool = false
var move_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	super._ready()
	move_velocity = Vector2(speed if is_moving_right else -speed, 0.0)
	velocity = move_velocity
	_apply_facing()

func _ai_process(delta: float) -> void:
	_patrol(delta)

func _probe_position() -> Vector2:
	var dir: float = 1.0 if is_moving_right else -1.0
	return global_position + Vector2(check_obstacle_distance * dir, 0.0)

func _patrol(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var probe: Vector2 = _probe_position()
	var ray := PhysicsRayQueryParameters2D.create(probe, probe + Vector2(0.0, fall_check_length), obstacle_mask)
	near_fall = space.intersect_ray(ray).is_empty()
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = wall_check_radius
	q.shape = circle
	q.transform = Transform2D(0.0, probe)
	q.collision_mask = obstacle_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	near_wall = not space.intersect_shape(q, 1).is_empty()

	if not near_fall and not near_wall:
		stabilized = true
	if stabilized and (near_fall or near_wall):
		stabilized = false
		_change_direction()
	if stabilized and not should_stop_moving:
		# Unity: rb.velocity = Vector2.Lerp(rb.velocity, moveVelocity, 0.1) per 0.02 s step.
		velocity = velocity.lerp(move_velocity, 1.0 - pow(1.0 - lerp_weight, delta / lerp_step))

func _change_direction() -> void:
	velocity = Vector2.ZERO
	is_moving_right = not is_moving_right
	move_velocity.x = speed if is_moving_right else -speed
	_apply_facing()

func _apply_facing() -> void:
	if visual != null:
		visual.scale.x = -1.0 if is_moving_right else 1.0
