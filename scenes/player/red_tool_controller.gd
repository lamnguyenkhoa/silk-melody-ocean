class_name RedToolController
extends Node
## Port of RedToolController.cs (child of the Player). `use_red_tool` is called by Player._handle_tool_usage
## after the gameplay gate / cooldown checks; each tool checks its own charge.

## Unity: Rigidbody2D.velocity (20, 0) -> 320 px/s.
const THROW_SPEED: float = 20.0 * 16.0
## Unity: Quaternion.Euler(0, 0, +-10) fan of the Triple Knife.
const KNIFE_SPREAD_DEG: float = 10.0
const THROW_BLADE_SCENE := "res://scenes/player/throw_blade_proj.tscn"
const TRIPLE_KNIFE_SCENE := "res://scenes/player/triple_knife_proj.tscn"
const LIFEBLOOD_PE_SCENE := "res://scenes/vfx/lifeblood_pe.tscn"
## Unity: LifebloodNeedleEffect LookRotation(+-1, 0.2, 0) -> emission direction (x mirrored, y flipped).
const LIFEBLOOD_PE_DIR := Vector2(1.0, -0.2)

@onready var player: Player = get_parent() as Player

## RedToolController.UseRedTool(toolName).
func use_red_tool(tool_id: int) -> void:
	match tool_id:
		InventoryIds.RedToolName.THROW_BLADE:
			use_throw_blade()
		InventoryIds.RedToolName.TRIPLE_KNIFE:
			use_triple_knife()
		InventoryIds.RedToolName.LIFEBLOOD_NEEDLE:
			use_lifeblood_needle()

func use_throw_blade() -> void:
	var id: int = InventoryIds.RedToolName.THROW_BLADE
	if GameState.get_red_tool_charge(id) <= 0.0:
		return
	var left: bool = player.is_facing_left
	var proj := _spawn(THROW_BLADE_SCENE)
	proj.launch(Vector2.LEFT if left else Vector2.RIGHT, THROW_SPEED, left)
	GameState.consume_red_tool_charge(id)
	player.sfx.play_sound(PlayerSfx.Sound.THROWING)

func use_triple_knife() -> void:
	var id: int = InventoryIds.RedToolName.TRIPLE_KNIFE
	if GameState.get_red_tool_charge(id) <= 0.0:
		return
	# Unity directions (y up): straight, +10 deg, -10 deg. Godot y is down.
	var rad: float = deg_to_rad(KNIFE_SPREAD_DEG)
	var straight := Vector2.RIGHT
	var spread1 := Vector2(cos(rad), -sin(rad))
	var spread2 := Vector2(cos(rad), sin(rad))
	var left: bool = player.is_facing_left
	# Facing left, Unity negates the whole vector (point reflection), not just x.
	var dirs: Array[Vector2] = [straight, spread1, spread2]
	for d: Vector2 in dirs:
		var proj := _spawn(TRIPLE_KNIFE_SCENE)
		proj.launch(-d if left else d, THROW_SPEED, left)
	GameState.consume_red_tool_charge(id)
	player.sfx.play_sound(PlayerSfx.Sound.THROWING)

## UseLifeBloodNeedle: not usable while any lifeblood is left; charge and sound are paid at the press, the
## lifeblood itself arrives with the clip's LifebloodNeedleEffect event.
func use_lifeblood_needle() -> void:
	if GameState.lifeblood_hp > 0:
		return
	var id: int = InventoryIds.RedToolName.LIFEBLOOD_NEEDLE
	if GameState.get_red_tool_charge(id) > 0.0:
		GameState.consume_red_tool_charge(id)
		player.play_lifeblood_needle_anim()
		player.sfx.play_sound(PlayerSfx.Sound.THROWING)

## LifebloodNeedlePE: a splash from the back, slightly upward.
func spawn_lifeblood_effect() -> void:
	var fx := (load(LIFEBLOOD_PE_SCENE) as PackedScene).instantiate() as CPUParticles2D
	_world_parent().add_child(fx)
	fx.global_position = player.global_position
	fx.direction = Vector2(-LIFEBLOOD_PE_DIR.x * player.facing(), LIFEBLOOD_PE_DIR.y)
	fx.emitting = true

## Instantiate(prefab, player.transform.position, identity) at the scene root; here: the current room.
func _spawn(scene_path: String) -> ToolProjectile:
	var proj := (load(scene_path) as PackedScene).instantiate() as ToolProjectile
	_world_parent().add_child(proj)
	proj.global_position = player.global_position
	return proj

func _world_parent() -> Node:
	if RoomLoader.current_room != null and is_instance_valid(RoomLoader.current_room):
		return RoomLoader.current_room
	return player.get_parent()
