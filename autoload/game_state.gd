extends Node
## Port of GameMaster.cs + PlayerData.cs + WorldData.cs + SaveSystem.cs (plan section 4).
## Player fields live directly on GameState (GameState.current_hp, ...);
## world data lives in GameState.world (GameState.world.enemy_kill_count, ...).

signal stats_changed

const PLAYER_SAVE_PATH := "user://player.json"
const WORLD_SAVE_PATH := "user://world.json"

class WorldData:
	extends RefCounted
	var visited_rooms: Array[String] = []
	## enemy_type (int) -> kill count (int)
	var enemy_kill_count: Dictionary = {}

# --- PlayerData (defaults = C# field defaults in PlayerData.cs) ---
var max_hp: int = 5
var current_hp: int = 5
## Blue bonus masks, absorb damage first.
var lifeblood_hp: int = 0
var current_silk: int = 0
var max_silk: int = 8
var silk_heal: int = 3
var damage: int = 4
## 7 u/s * 16
var move_speed: float = 112.0
## 12 u/s * 16 (applied upwards as -jump_force)
var jump_force: float = 192.0
## 20 u/s * 16
var dash_force: float = 320.0
var max_dash: int = 1
var extra_jump: int = 0
var dash_time: float = 0.25
## 5 u/s * 16
var enemy_knockback_power: float = 80.0
var attack_cooldown: float = 0.15
var parry_window: float = 0.25
var parry_cooldown: float = 1.0
## Unused for now (tool code paths are out of scope).
var tool_cooldown: float = 0.35
var stun_time: float = 0.4
var i_frame_time: float = 1.5
var respawn_scene: String = "DirtCave0"
var respawn_chair_name: String = ""
var respawn_pos: Vector2 = Vector2.ZERO
var copper_shard: int = 0
var scale_shard: int = 0

var world: WorldData = WorldData.new()

func _ready() -> void:
	reset_to_new_game()

## GameMaster.InitNewGameData(): fresh PlayerData + WorldData with the defaults above.
func reset_to_new_game() -> void:
	max_hp = 5
	current_hp = 5
	lifeblood_hp = 0
	current_silk = 0
	max_silk = 8
	silk_heal = 3
	damage = 4
	move_speed = 112.0
	jump_force = 192.0
	dash_force = 320.0
	max_dash = 1
	extra_jump = 0
	dash_time = 0.25
	enemy_knockback_power = 80.0
	attack_cooldown = 0.15
	parry_window = 0.25
	parry_cooldown = 1.0
	tool_cooldown = 0.35
	stun_time = 0.4
	i_frame_time = 1.5
	respawn_scene = "DirtCave0"
	respawn_chair_name = ""
	respawn_pos = Vector2.ZERO
	copper_shard = 0
	scale_shard = 0
	world = WorldData.new()
	stats_changed.emit()

func add_visited_room(room_name: String) -> void:
	if not world.visited_rooms.has(room_name):
		world.visited_rooms.append(room_name)

# --- Save system (SaveSystem.cs) ---

func save() -> void:
	_write_json(PLAYER_SAVE_PATH, _player_to_dict())
	_write_json(WORLD_SAVE_PATH, _world_to_dict())

## Overwrites only the fields present in the save files. Returns false if no save exists.
func load_save() -> bool:
	if not save_exists():
		return false
	var p: Variant = _read_json(PLAYER_SAVE_PATH)
	if p is Dictionary:
		_apply_player_dict(p)
	var w: Variant = _read_json(WORLD_SAVE_PATH)
	if w is Dictionary:
		_apply_world_dict(w)
	stats_changed.emit()
	return true

func delete_save() -> void:
	for path: String in [PLAYER_SAVE_PATH, WORLD_SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func save_exists() -> bool:
	return FileAccess.file_exists(PLAYER_SAVE_PATH)

# --- internals ---

func _player_to_dict() -> Dictionary:
	return {
		"max_hp": max_hp,
		"current_hp": current_hp,
		"lifeblood_hp": lifeblood_hp,
		"current_silk": current_silk,
		"max_silk": max_silk,
		"silk_heal": silk_heal,
		"damage": damage,
		"move_speed": move_speed,
		"jump_force": jump_force,
		"dash_force": dash_force,
		"max_dash": max_dash,
		"extra_jump": extra_jump,
		"dash_time": dash_time,
		"enemy_knockback_power": enemy_knockback_power,
		"attack_cooldown": attack_cooldown,
		"parry_window": parry_window,
		"parry_cooldown": parry_cooldown,
		"tool_cooldown": tool_cooldown,
		"stun_time": stun_time,
		"i_frame_time": i_frame_time,
		"respawn_scene": respawn_scene,
		"respawn_chair_name": respawn_chair_name,
		"respawn_pos": [respawn_pos.x, respawn_pos.y],
		"copper_shard": copper_shard,
		"scale_shard": scale_shard,
	}

func _world_to_dict() -> Dictionary:
	var kills: Dictionary = {}
	for k: Variant in world.enemy_kill_count:
		kills[str(k)] = world.enemy_kill_count[k]
	return {
		"visited_rooms": world.visited_rooms.duplicate(),
		"enemy_kill_count": kills,
	}

func _apply_player_dict(d: Dictionary) -> void:
	if d.has("max_hp"): max_hp = int(d["max_hp"])
	if d.has("current_hp"): current_hp = int(d["current_hp"])
	if d.has("lifeblood_hp"): lifeblood_hp = int(d["lifeblood_hp"])
	if d.has("current_silk"): current_silk = int(d["current_silk"])
	if d.has("max_silk"): max_silk = int(d["max_silk"])
	if d.has("silk_heal"): silk_heal = int(d["silk_heal"])
	if d.has("damage"): damage = int(d["damage"])
	if d.has("move_speed"): move_speed = float(d["move_speed"])
	if d.has("jump_force"): jump_force = float(d["jump_force"])
	if d.has("dash_force"): dash_force = float(d["dash_force"])
	if d.has("max_dash"): max_dash = int(d["max_dash"])
	if d.has("extra_jump"): extra_jump = int(d["extra_jump"])
	if d.has("dash_time"): dash_time = float(d["dash_time"])
	if d.has("enemy_knockback_power"): enemy_knockback_power = float(d["enemy_knockback_power"])
	if d.has("attack_cooldown"): attack_cooldown = float(d["attack_cooldown"])
	if d.has("parry_window"): parry_window = float(d["parry_window"])
	if d.has("parry_cooldown"): parry_cooldown = float(d["parry_cooldown"])
	if d.has("tool_cooldown"): tool_cooldown = float(d["tool_cooldown"])
	if d.has("stun_time"): stun_time = float(d["stun_time"])
	if d.has("i_frame_time"): i_frame_time = float(d["i_frame_time"])
	if d.has("respawn_scene"): respawn_scene = str(d["respawn_scene"])
	if d.has("respawn_chair_name"): respawn_chair_name = str(d["respawn_chair_name"])
	if d.has("respawn_pos"):
		var a: Variant = d["respawn_pos"]
		if a is Array and (a as Array).size() >= 2:
			respawn_pos = Vector2(float(a[0]), float(a[1]))
	if d.has("copper_shard"): copper_shard = int(d["copper_shard"])
	if d.has("scale_shard"): scale_shard = int(d["scale_shard"])

func _apply_world_dict(d: Dictionary) -> void:
	if d.has("visited_rooms"):
		world.visited_rooms.clear()
		for r: Variant in d["visited_rooms"]:
			world.visited_rooms.append(str(r))
	if d.has("enemy_kill_count"):
		world.enemy_kill_count.clear()
		var kills: Dictionary = d["enemy_kill_count"]
		for k: Variant in kills:
			world.enemy_kill_count[int(str(k))] = int(kills[k])

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)
