class_name PlayerStats
extends Resource
## Player-prefab-only tuning (Tenroh.prefab), NOT part of PlayerData. Values are
## already converted to Godot space (1 Unity unit = 16 px, y flipped). See plan §4.

## Unity: Rigidbody2D.gravityScale 5 * 9.81 = 49.05 u/s^2 (Tenroh.prefab).
@export var gravity: float = 784.8
## Unity: Rigidbody2D.linearDrag (Tenroh.prefab). Applied as v *= 1 / (1 + drag * dt).
@export var linear_drag: float = 2.0
## Unity: Player.maxJumpTime (prefab overrides the 0.5 code default), seconds.
@export var max_jump_time: float = 0.3
## Unity: Player.coyoteTime (Tenroh.prefab), seconds.
@export var coyote_time: float = 0.2
## Unity: Player.dashRecoil (0, 25) -> Godot (0, -400) px/s.
@export var dash_recoil: Vector2 = Vector2(0, -400)

## Unity: body CapsuleCollider/BoxCollider2D size 0.802 x 1.435 -> px.
@export var collider_size: Vector2 = Vector2(12.8, 23.0)
## Unity: body collider offset (0, -0.170) -> px, y flipped.
@export var collider_offset: Vector2 = Vector2(0, 2.7)

## Unity: groundCheck box at (0, -0.889), size (body.x - 0.05, 0.1) -> px (optional ShapeCast).
@export var ground_check_offset: Vector2 = Vector2(0, 14.2)
@export var ground_check_size: Vector2 = Vector2(12, 1.6)

## Unity: ledge "green" probe, offset (0.5 * facing, 0), size 0.2 x 0.1. X is mirrored by facing.
@export var ledge_green_offset: Vector2 = Vector2(8, 0)
## Unity: ledge "red" probe, offset (0.5 * facing, 0.5) -> y flipped. X is mirrored by facing.
@export var ledge_red_offset: Vector2 = Vector2(8, -8)
@export var ledge_probe_size: Vector2 = Vector2(3.2, 1.6)

## Unity: Player.DashAttackPos (1, -0.3) -> px.
@export var dash_attack_pos: Vector2 = Vector2(16, 4.8)
## Unity: Player.PogoAttackPos (0.27, -0.47) -> px.
@export var pogo_attack_pos: Vector2 = Vector2(4.3, 7.5)

## Unity: Player.footstepFrequency, seconds.
@export var footstep_frequency: float = 0.5
