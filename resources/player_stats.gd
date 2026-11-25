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

## Unity: DustPE local position (0.109, -0.838) -> px (y flipped).
@export var dust_offset: Vector2 = Vector2(1.7, 13.4)
## Unity: HandleMovement speedModifier while slowed (hard-coded 0.5f).
@export var slowed_speed_modifier: float = 0.5

# --- P3: combat tuning (Player.cs / Tenroh.prefab values, Godot space) ---

## Unity: HandleAttack verInput >= 0.1 / <= -0.1 thresholds.
@export var ver_input_threshold: float = 0.1
## Unity: AttackDealDamage normal slash local position (1, 0) -> px.
@export var slash_forward_pos: Vector2 = Vector2(16, 0)
## Unity: AttackDealDamage up slash local position (0, 0.5) -> px, y flipped.
@export var slash_up_pos: Vector2 = Vector2(0, -8)
## Unity: AttackDealDamage up slash local rotation +90 deg -> -90 deg (y flipped).
@export var slash_up_rotation_deg: float = -90.0

## Unity: Damaged() rb.AddForce(knockbackDir * 5 + up * 5) -> px/s. Horizontal part.
@export var hurt_knockback: float = 80.0
## Unity: Damaged() rb.AddForce(... + Vector3.up * 5) -> (0, -80) px/s.
@export var hurt_knockback_up: Vector2 = Vector2(0, -80)
## Unity: DamagedFreezeTime 0.35 s (real time) per point of damage.
@export var hurt_freeze_per_damage: float = 0.35
## Unity: CinemachineShake.ShakeCamera(5, 0.3, true) from Damaged().
@export var damage_shake_intensity: float = 5.0
@export var damage_shake_time: float = 0.3
## Unity: Damaged() hurt spark random rotation +-15 deg.
@export var hurt_spark_rotation_deg: float = 15.0
## Unity: IFrame() sprite alpha 0.5.
@export var i_frame_alpha: float = 0.5
## Unity: contact damage amount (OnCollisionEnter2D -> Damaged(1, ...)).
@export var contact_damage: int = 1

## Unity: ParryRipose freeze (WaitForSecondsRealtime 0.35).
@export var parry_freeze_time: float = 0.35
## Unity: ParryRipose dash force multiplier (dashForce * 1.5).
@export var riposte_dash_multiplier: float = 1.5
## Unity: ParryRipose "Bonus iFrame time" 0.1 s.
@export var riposte_i_frame_tail: float = 0.1

## Unity: GotParalyzed 1 s / GotSlowed 2 s / drained silk 2.
@export var paralyzed_time: float = 1.0
@export var slowed_time: float = 2.0
@export var drained_silk: int = 2
## Unity: FlashWhite() 0.25 s.
@export var flash_white_time: float = 0.25
## Re-check Hurtbox overlaps this many physics ticks after i-frames end (Godot-only addition).
@export var contact_recheck_ticks: int = 2

# --- M2: red tools (RedToolController / Player.LifebloodNeedleEffect) ---

## Unity: LifebloodNeedleEffect `lifebloodHp += 2`.
@export var lifeblood_needle_amount: int = 2
## Unity: FlashBlue WaitForSeconds(0.15).
@export var lifeblood_flash_time: float = 0.15

# --- P4: silk skills (Player.cs HandleSilkSkill / BeginHeal ... CatchSilkBurstRecoil) ---

## Unity: HandleSilkSkill hard-coded silk costs (paid at press).
@export var gossamer_cost: int = 6
@export var silk_burst_cost: int = 4
@export var heal_cost: int = 8
## Unity: BeginHeal / BeginGossamer localPosition (0.25, 0, 0) -> px (SilkBind VFX + Gossamer).
@export var skill_vfx_pos: Vector2 = Vector2(4, 0)
## Unity: ThrowSilkBurst localPosition (4, 0, 0) -> px.
@export var silk_burst_pos: Vector2 = Vector2(64, 0)
## Unity: CatchSilkBurstRecoil AddForce(-+(10, 2)) impulse -> px/s, written for a right-facing player
## (x is mirrored by facing, y flipped).
@export var silk_burst_recoil: Vector2 = Vector2(-160, -32)
