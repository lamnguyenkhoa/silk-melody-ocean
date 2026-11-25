extends Node
## Port of GameMaster.cs + PlayerData.cs + WorldData.cs + SaveSystem.cs (plan section 4).
## Player fields live directly on GameState (GameState.current_hp, ...);
## world data lives in GameState.world (GameState.world.enemy_kill_count, ...).

signal stats_changed
## GameMaster.OnTalismanChange: fired whenever tools are equipped / unequipped or the talisman changes.
signal talisman_changed

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
## Red tool use cooldown (PlayerData.toolCooldown 0.35 s).
var tool_cooldown: float = 0.35
var stun_time: float = 0.4
var i_frame_time: float = 1.5
var respawn_scene: String = "DirtCave0"
var respawn_chair_name: String = ""
var respawn_pos: Vector2 = Vector2.ZERO
var copper_shard: int = 0
var scale_shard: int = 0

# --- PlayerData inventory / talisman / tools (M1 data, equip / use behaviour in M2) ---
## Amount per ItemName (inventoryItemAmount).
var inventory_item_amount: Array[int] = []
## TalismanName values.
var found_talismans: Array[int] = []
var equipped_talisman: int = InventoryIds.TalismanName.WANDERER
## Current charge per RedToolName (redToolsCurrentCharge).
var red_tools_current_charge: Array[float] = []
var found_red_tools: Array[int] = []
var equipped_red_tools: Array[int] = []
var selected_red_tool_id: int = 0
var found_blue_tools: Array[int] = []
var equipped_blue_tools: Array[int] = []
var found_yellow_tools: Array[int] = []
var equipped_yellow_tools: Array[int] = []

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
	_reset_inventory()
	world = WorldData.new()
	stats_changed.emit()

## InitNewGameData part: talismans [wanderer], full red-tool charges, starting items, no tools found.
func _reset_inventory() -> void:
	inventory_item_amount = _new_game_items()
	found_talismans = [InventoryIds.TalismanName.WANDERER]
	equipped_talisman = InventoryIds.TalismanName.WANDERER
	red_tools_current_charge = _full_red_tool_charges()
	found_red_tools = []
	equipped_red_tools = []
	selected_red_tool_id = 0
	found_blue_tools = []
	equipped_blue_tools = []
	found_yellow_tools = []
	equipped_yellow_tools = []

func _new_game_items() -> Array[int]:
	var items: Array[int] = []
	items.resize(InventoryIds.ItemName.size())
	items.fill(0)
	for item: int in InventoryIds.NEW_GAME_ITEMS:
		items[item] = 1
	return items

func _full_red_tool_charges() -> Array[float]:
	var charges: Array[float] = []
	charges.assign(InventoryIds.RED_TOOL_MAX_CHARGE)
	return charges

func get_item_amount(item: int) -> int:
	if item < 0 or item >= inventory_item_amount.size():
		return 0
	return inventory_item_amount[item]

func get_kill_count(enemy_type: int) -> int:
	return int(world.enemy_kill_count.get(enemy_type, 0))

## Unity's editor-only `debugInventory` flag (GameMaster.InitNewGameData): every talisman that has a prefab
## (Wanderer, Sentinel: GameMaster.talismanData has no Toolmaster) and every tool is found. Called from the
## debug-build key (F8) in world.gd.
func grant_debug_inventory() -> void:
	for t: int in ToolData.layout_talismans():
		if not found_talismans.has(t):
			found_talismans.append(t)
	for t: int in InventoryIds.RedToolName.values():
		if not found_red_tools.has(t):
			found_red_tools.append(t)
	for t: int in InventoryIds.BlueToolName.values():
		if not found_blue_tools.has(t):
			found_blue_tools.append(t)
	for t: int in InventoryIds.YellowToolName.values():
		if not found_yellow_tools.has(t):
			found_yellow_tools.append(t)
	talisman_changed.emit()
	stats_changed.emit()

# --- Talisman / tools (GameMaster.cs) ---

## The talisman whose crest is shown (GameMaster.equippedTalisman). An equipped talisman that is not in
## foundTalismans falls back to the Wanderer, the prefab the inventory menu starts with.
func effective_talisman() -> int:
	if found_talismans.has(equipped_talisman):
		return equipped_talisman
	return InventoryIds.TalismanName.WANDERER

func red_slot_count() -> int:
	return (ToolData.layout(effective_talisman())["red"] as Array).size()

func blue_slot_count() -> int:
	return (ToolData.layout(effective_talisman())["blue"] as Array).size()

func yellow_slot_count() -> int:
	return (ToolData.layout(effective_talisman())["yellow"] as Array).size()

## GameMaster.ChangeToNextTalisman: cycles foundTalismans (wraps) and unequips every tool.
func change_to_next_talisman() -> void:
	if found_talismans.size() <= 1:
		return
	unequip_all_tools()
	var index: int = found_talismans.find(effective_talisman())
	index += 1
	if index > found_talismans.size() - 1:
		index = 0
	equipped_talisman = found_talismans[index]
	talisman_changed.emit()
	stats_changed.emit()

## GameMaster.UnequipAllTools (selectedRedToolId is left alone, like Unity).
func unequip_all_tools() -> void:
	equipped_red_tools.clear()
	equipped_blue_tools.clear()
	equipped_yellow_tools.clear()
	talisman_changed.emit()
	stats_changed.emit()

## GameMaster.RefillRedTool (rest chair): every red tool back to maxCharge.
func refill_red_tools() -> void:
	red_tools_current_charge = _full_red_tool_charges()
	stats_changed.emit()

## GameMaster.SwapTool(rightDirection): cycles the selected red tool, wraps.
func swap_tool(right_direction: bool) -> void:
	if equipped_red_tools.is_empty():
		return
	if right_direction:
		selected_red_tool_id += 1
	else:
		selected_red_tool_id -= 1
	if selected_red_tool_id > equipped_red_tools.size() - 1:
		selected_red_tool_id = 0
	if selected_red_tool_id < 0:
		selected_red_tool_id = equipped_red_tools.size() - 1
	stats_changed.emit()

## The selected red tool (RedToolName) or -1 when none is equipped / the index is out of range.
func get_selected_red_tool() -> int:
	if selected_red_tool_id < 0 or selected_red_tool_id >= equipped_red_tools.size():
		return -1
	return equipped_red_tools[selected_red_tool_id]

func get_red_tool_charge(tool_id: int) -> float:
	if tool_id < 0 or tool_id >= red_tools_current_charge.size():
		return 0.0
	return red_tools_current_charge[tool_id]

## Uses one charge of a red tool (the controllers did `redToolsCurrentCharge[id] -= 1`).
func consume_red_tool_charge(tool_id: int) -> void:
	if tool_id < 0 or tool_id >= red_tools_current_charge.size():
		return
	red_tools_current_charge[tool_id] -= 1.0
	stats_changed.emit()

## GameMaster.EquipUnequipRedTool: toggles; equipping needs a free slot on the talisman.
func equip_unequip_red_tool(tool_id: int) -> void:
	if equipped_red_tools.has(tool_id):
		equipped_red_tools.erase(tool_id)
	elif equipped_red_tools.size() < red_slot_count():
		equipped_red_tools.append(tool_id)
	# Remove unequipped but selected tool.
	if selected_red_tool_id >= equipped_red_tools.size():
		if equipped_red_tools.size() > 0:
			selected_red_tool_id = 0
	talisman_changed.emit()
	stats_changed.emit()

func equip_unequip_blue_tool(tool_id: int) -> void:
	_toggle_tool(equipped_blue_tools, tool_id, blue_slot_count())

func equip_unequip_yellow_tool(tool_id: int) -> void:
	_toggle_tool(equipped_yellow_tools, tool_id, yellow_slot_count())

func _toggle_tool(list: Array[int], tool_id: int, slots: int) -> void:
	if list.has(tool_id):
		list.erase(tool_id)
	elif list.size() < slots:
		list.append(tool_id)
	talisman_changed.emit()
	stats_changed.emit()

## Stat helpers: every gameplay change of hp / lifeblood / silk / shards goes through here (or emits
## stats_changed itself) so the HUD (which listens to the signal, never polls) stays in sync.
func add_silk(amount: int) -> void:
	current_silk = clampi(current_silk + amount, 0, max_silk)
	stats_changed.emit()

func add_lifeblood(amount: int) -> void:
	lifeblood_hp = maxi(lifeblood_hp + amount, 0)
	stats_changed.emit()

func add_copper_shard(amount: int) -> void:
	copper_shard = maxi(copper_shard + amount, 0)
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
	talisman_changed.emit()
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
		"inventory_item_amount": inventory_item_amount.duplicate(),
		"found_talismans": found_talismans.duplicate(),
		"equipped_talisman": equipped_talisman,
		"red_tools_current_charge": red_tools_current_charge.duplicate(),
		"found_red_tools": found_red_tools.duplicate(),
		"equipped_red_tools": equipped_red_tools.duplicate(),
		"selected_red_tool_id": selected_red_tool_id,
		"found_blue_tools": found_blue_tools.duplicate(),
		"equipped_blue_tools": equipped_blue_tools.duplicate(),
		"found_yellow_tools": found_yellow_tools.duplicate(),
		"equipped_yellow_tools": equipped_yellow_tools.duplicate(),
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
	_apply_inventory_dict(d)

## Old saves (before M1) lack these keys: every missing key falls back to the new-game value
## (not to whatever is in memory), so loading an old save never leaves stale inventory data behind.
func _apply_inventory_dict(d: Dictionary) -> void:
	_reset_inventory()
	if d.has("inventory_item_amount"):
		var amounts: Array[int] = _new_game_items()
		amounts.fill(0) # a saved array is the whole truth; unsaved trailing items count as 0
		var src: Array = _as_array(d["inventory_item_amount"])
		for i in mini(src.size(), amounts.size()):
			amounts[i] = int(src[i])
		inventory_item_amount = amounts
	if d.has("found_talismans"):
		found_talismans = _int_list(d["found_talismans"])
	if d.has("equipped_talisman"):
		equipped_talisman = int(d["equipped_talisman"])
	if d.has("red_tools_current_charge"):
		var charges: Array[float] = _full_red_tool_charges()
		var csrc: Array = _as_array(d["red_tools_current_charge"])
		for i in mini(csrc.size(), charges.size()):
			charges[i] = float(csrc[i])
		red_tools_current_charge = charges
	if d.has("found_red_tools"):
		found_red_tools = _int_list(d["found_red_tools"])
	if d.has("equipped_red_tools"):
		equipped_red_tools = _int_list(d["equipped_red_tools"])
	if d.has("selected_red_tool_id"):
		selected_red_tool_id = int(d["selected_red_tool_id"])
	if d.has("found_blue_tools"):
		found_blue_tools = _int_list(d["found_blue_tools"])
	if d.has("equipped_blue_tools"):
		equipped_blue_tools = _int_list(d["equipped_blue_tools"])
	if d.has("found_yellow_tools"):
		found_yellow_tools = _int_list(d["found_yellow_tools"])
	if d.has("equipped_yellow_tools"):
		equipped_yellow_tools = _int_list(d["equipped_yellow_tools"])

static func _as_array(v: Variant) -> Array:
	return v if v is Array else []

static func _int_list(v: Variant) -> Array[int]:
	var out: Array[int] = []
	for e: Variant in _as_array(v):
		out.append(int(e))
	return out

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
