extends SceneTree
## Automated test of the talisman tab and the red tools (plan 13, phase M2).
##  Part 1 (pure data, no scene): talisman slot counts, change talisman, slot limits, swap wrap, save round trip.
##  Part 2 (flat constructed room, real player + training dummy): Throw Blade / Triple Knife / Lifeblood Needle
##    (projectile count, speed, direction, damage on an enemy, charges, cooldown, gating, lifeblood effect),
##    rest chair refill.
##  Part 3 (real world scene, real key events): F8 debug grant, Talisman tab (equip only while resting, equip
##    state, crest slots, info box, change talisman), tool use / swap with the menu open, HUD charge circle.
## Run: godot --headless --path . -s tools/test_tools.gd
## Physics runs at 60 Hz. Any existing user save is backed up and restored.

const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const DUMMY_PATH := "res://scenes/enemies/training_dummy.tscn"
const CHAIR_PATH := "res://scenes/interactables/rest_chair.tscn"
const BLADE_PATH := "res://scenes/player/throw_blade_proj.tscn"
const KNIFE_PATH := "res://scenes/player/triple_knife_proj.tscn"
const WORLD_PATH := "res://scenes/world/world.tscn"
const SAVE_FILES: Array[String] = ["user://player.json", "user://world.json"]
const SOLID_ATLAS := Vector2i(3, 3)
const FLOOR_X := [-40, 40]
const FLOOR_Y := [0, 2]
const REST_Y := -14.3
const DUMMY_REST_Y := -14.75
const FPS := 60.0
const NEW_GAME := 0
## Plain ints (class names / autoload enums are not resolvable at compile time in -s scripts).
const RED_BLADE := 0
const RED_KNIFE := 1
const RED_NEEDLE := 2
const SOUND_THROWING := 8
const SOUND_SYRINGE := 9
const TAB_TALISMAN := 1

var gs
var rl
var player
var dummy
var bare_nodes: Array = []
var world
var gm
var hud
var rows: Array = []
var fails: int = 0
var _backup: Dictionary = {}
var _changed_signals: int = 0


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	rl = root.get_node("RoomLoader")
	_backup_saves()
	gs.delete_save()
	gs.talisman_changed.connect(func() -> void: _changed_signals += 1)

	_test_slot_counts()
	_test_slot_limits()
	_test_change_talisman()
	_test_swap()
	_test_save_roundtrip()

	await _build_bare_scene()
	await _test_throw_blade()
	await _test_triple_knife()
	await _test_charges_and_zero()
	await _test_cooldown()
	await _test_gating()
	await _test_lifeblood_needle()
	await _test_swap_key()
	await _test_chair_refill()
	_free_bare_scene()
	await process_frame

	await _boot_world()
	await _test_debug_grant()
	await _test_tab_not_resting()
	await _test_tab_resting()
	await _test_tab_unfound()
	await _test_menu_blocks_tools()
	await _test_world_tool_use()
	await _test_hud()

	if world != null and is_instance_valid(world):
		world.free()
	paused = false
	Engine.time_scale = 1.0
	await process_frame
	_restore_saves()
	_print_table()
	quit(1 if fails > 0 else 0)


# --- helpers ---

func _backup_saves() -> void:
	for p in SAVE_FILES:
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)

func _restore_saves() -> void:
	gs.delete_save()
	for p in _backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(_backup[p])
		f.close()

func _add(name: String, measured: String, expected: String, ok: bool, note: String = "") -> void:
	rows.append([name, measured, expected, "PASS" if ok else "FAIL", note])
	if not ok:
		fails += 1

func _check(name: String, ok: bool, note: String = "") -> void:
	_add(name, str(ok), "true", ok, note)

func _eq(name: String, measured, expected) -> void:
	_add(name, str(measured), str(expected), measured == expected)

func _near(name: String, measured: float, expected: float, tol: float, note: String = "") -> void:
	_add(name, "%.3f" % measured, "%.3f +-%.3f" % [expected, tol], absf(measured - expected) <= tol, note)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Waits until cond is true; returns the number of physics frames waited, or -1 on timeout.
func _wait_until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		await physics_frame
		if cond.call():
			return i + 1
	return -1

func _act(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()

## Input is injected in the process phase (like real events): inside the physics_frame callback the edge
## would be seen by two consecutive physics ticks (the player's buffered edge plus Input.is_action_just_pressed).
func _tap(action: StringName) -> void:
	await process_frame
	_act(action, true)
	await physics_frame
	_act(action, false)

func _send_key(keycode: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _key(keycode: Key) -> void:
	await process_frame
	_send_key(keycode, true)
	await physics_frame
	_send_key(keycode, false)
	await physics_frame
	await physics_frame

func _arr(list: Array) -> Array:
	return list.duplicate()

func _set_list(target: Array, values: Array) -> void:
	target.assign(values)

func _projectiles() -> Array:
	var out: Array = []
	for n in get_nodes_in_group("projectiles"):
		if n.has_method("launch"):
			out.append(n)
	return out

func _clear_projectiles() -> void:
	for n in _projectiles():
		n.free()
	for n in root.get_children():
		if n is CPUParticles2D and n.name == "LifebloodNeedlePE":
			n.free()


# --- part 1: data ---

func _test_slot_counts() -> void:
	gs.reset_to_new_game()
	_eq("slots: Wanderer red / blue / yellow", [gs.red_slot_count(), gs.blue_slot_count(), gs.yellow_slot_count()], [1, 1, 1])
	gs.found_talismans.assign([0, 1])
	gs.equipped_talisman = 1
	_eq("slots: Sentinel red / blue / yellow", [gs.red_slot_count(), gs.blue_slot_count(), gs.yellow_slot_count()], [2, 2, 0])
	gs.found_talismans.assign([0])
	_eq("slots: equipped but not found -> Wanderer layout", gs.effective_talisman(), 0)
	gs.found_talismans.assign([0, 1, 2])
	gs.equipped_talisman = 2
	_eq("slots: Toolmaster (no prefab) has no slots", [gs.red_slot_count(), gs.blue_slot_count(), gs.yellow_slot_count()], [0, 0, 0])
	gs.reset_to_new_game()
	_eq("debug grant talismans = those with a prefab", (func() -> Array:
		gs.grant_debug_inventory()
		return _arr(gs.found_talismans)).call(), [0, 1])

func _test_slot_limits() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.equip_unequip_red_tool(RED_BLADE)
	gs.equip_unequip_red_tool(RED_KNIFE)
	_eq("limits Wanderer: 1 red slot, second tool refused", gs.equipped_red_tools, [0])
	gs.equip_unequip_blue_tool(0)
	gs.equip_unequip_blue_tool(1)
	_eq("limits Wanderer: 1 blue slot", gs.equipped_blue_tools, [0])
	gs.equip_unequip_yellow_tool(0)
	_eq("limits Wanderer: 1 yellow slot", gs.equipped_yellow_tools, [0])
	gs.equip_unequip_red_tool(RED_BLADE)
	_eq("limits: equipping an equipped tool unequips it", gs.equipped_red_tools, [])
	gs.unequip_all_tools()
	gs.equipped_talisman = 1
	gs.equip_unequip_red_tool(RED_NEEDLE)
	gs.equip_unequip_red_tool(RED_BLADE)
	gs.equip_unequip_red_tool(RED_KNIFE)
	_eq("limits Sentinel: 2 red slots, in equip order, third refused", gs.equipped_red_tools, [2, 0])
	gs.equip_unequip_blue_tool(1)
	gs.equip_unequip_blue_tool(0)
	_eq("limits Sentinel: 2 blue slots", gs.equipped_blue_tools, [1, 0])
	gs.equip_unequip_yellow_tool(0)
	_eq("limits Sentinel: no yellow slot", gs.equipped_yellow_tools, [])
	gs.selected_red_tool_id = 1
	gs.equip_unequip_red_tool(RED_BLADE) # unequip the selected one (index 1)
	_eq("limits: selected id falls back to 0 when its tool was unequipped", gs.selected_red_tool_id, 0)

func _test_change_talisman() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.equip_unequip_red_tool(RED_KNIFE)
	gs.equip_unequip_blue_tool(0)
	gs.equip_unequip_yellow_tool(0)
	_changed_signals = 0
	gs.change_to_next_talisman()
	_eq("change talisman: Wanderer -> Sentinel", gs.equipped_talisman, 1)
	_eq("change talisman: unequips every tool", [gs.equipped_red_tools, gs.equipped_blue_tools, gs.equipped_yellow_tools], [[], [], []])
	_check("change talisman: talisman_changed emitted", _changed_signals >= 1)
	gs.change_to_next_talisman()
	_eq("change talisman: wraps Sentinel -> Wanderer", gs.equipped_talisman, 0)
	gs.found_talismans.assign([0, 1, 2])
	gs.change_to_next_talisman()
	gs.change_to_next_talisman()
	_eq("change talisman: cycles through foundTalismans order (0 -> 1 -> 2)", gs.equipped_talisman, 2)
	gs.change_to_next_talisman()
	_eq("change talisman: 2 -> 0", gs.equipped_talisman, 0)
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.found_talismans.assign([0])
	gs.equip_unequip_red_tool(RED_BLADE)
	gs.change_to_next_talisman()
	_eq("change talisman: a single found talisman changes nothing (tools stay)", [gs.equipped_talisman, gs.equipped_red_tools], [0, [0]])

func _test_swap() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.swap_tool(true)
	_eq("swap: nothing equipped -> no change", gs.selected_red_tool_id, 0)
	gs.equipped_talisman = 1
	gs.equip_unequip_red_tool(RED_NEEDLE)
	gs.equip_unequip_red_tool(RED_BLADE)
	gs.swap_tool(true)
	_eq("swap right: 0 -> 1", gs.selected_red_tool_id, 1)
	gs.swap_tool(true)
	_eq("swap right: wraps 1 -> 0", gs.selected_red_tool_id, 0)
	gs.swap_tool(false)
	_eq("swap left: wraps 0 -> 1", gs.selected_red_tool_id, 1)
	_eq("selected red tool id -> tool", gs.get_selected_red_tool(), RED_BLADE)
	gs.selected_red_tool_id = 5
	_eq("selected tool out of range -> -1 (no crash)", gs.get_selected_red_tool(), -1)

func _test_save_roundtrip() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.equipped_talisman = 1
	gs.equip_unequip_red_tool(RED_NEEDLE)
	gs.equip_unequip_red_tool(RED_KNIFE)
	gs.equip_unequip_blue_tool(1)
	gs.selected_red_tool_id = 1
	gs.red_tools_current_charge.assign([7.0, 2.0, 1.0])
	gs.save()
	gs.reset_to_new_game()
	_check("save: memory wiped", gs.equipped_red_tools.is_empty() and gs.equipped_talisman == 0)
	_check("save: load_save ok", gs.load_save())
	_eq("save round trip: talisman", gs.equipped_talisman, 1)
	_eq("save round trip: equipped red / blue / yellow", [gs.equipped_red_tools, gs.equipped_blue_tools, gs.equipped_yellow_tools], [[2, 1], [1], []])
	_eq("save round trip: selected tool id", gs.selected_red_tool_id, 1)
	_eq("save round trip: charges", gs.red_tools_current_charge, [7.0, 2.0, 1.0])
	_eq("save round trip: found tools", [gs.found_red_tools, gs.found_blue_tools, gs.found_yellow_tools, gs.found_talismans], [[0, 1, 2], [0, 1], [0], [0, 1]])
	gs.delete_save()


# --- part 2: constructed room ---

func _build_bare_scene() -> void:
	var tilemap := TileMapLayer.new()
	tilemap.name = "Tilemap"
	tilemap.tile_set = load(TILESET_PATH) as TileSet
	root.add_child(tilemap)
	bare_nodes.append(tilemap)
	for x in range(FLOOR_X[0] as int, (FLOOR_X[1] as int) + 1):
		for y in range(FLOOR_Y[0] as int, (FLOOR_Y[1] as int) + 1):
			tilemap.set_cell(Vector2i(x, y), 0, SOLID_ATLAS)
	player = (load(PLAYER_PATH) as PackedScene).instantiate()
	root.add_child(player)
	bare_nodes.append(player)
	player.global_position = Vector2(0, REST_Y)
	await _frames(20)

func _free_bare_scene() -> void:
	_clear_projectiles()
	for n in bare_nodes:
		if is_instance_valid(n):
			n.free()
	bare_nodes.clear()
	if dummy != null and is_instance_valid(dummy):
		dummy.free()
	dummy = null
	player = null

func _reset(x: float = 0.0) -> void:
	for a: StringName in [&"move_left", &"move_right", &"use_red_tool", &"swap_tool_right"]:
		if Input.is_action_pressed(a):
			_act(a, false)
	await _frames(3)
	_clear_projectiles()
	if dummy != null and is_instance_valid(dummy):
		dummy.free()
	dummy = null
	Engine.time_scale = 1.0
	player.rest_chair_recovery()
	player.anim.stop()
	player.anim_override = &""
	player.global_position = Vector2(x, REST_Y)
	player.velocity = Vector2.ZERO
	player.is_dashing = false
	player.is_dead = false
	player.is_kinematic = false
	player.control_lock = 0
	player.gravity_on = true
	player.is_facing_left = false
	player.visual.scale.x = 1.0
	player.in_attack = false
	player.in_menu = false
	player.resting = false
	player.tool_anim_lock = false
	player.hurtbox.monitoring = true
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	await _frames(10)
	player.tool_timer = 10.0

func _equip(tools: Array, talisman: int = 0) -> void:
	gs.equipped_talisman = talisman
	gs.equipped_red_tools.assign(tools)
	gs.selected_red_tool_id = 0

func _spawn_dummy(pos: Vector2) -> void:
	dummy = (load(DUMMY_PATH) as PackedScene).instantiate()
	dummy.position = pos
	root.add_child(dummy)

func _sound_playing(index: int) -> bool:
	var players: Dictionary = player.sfx.get("_players")
	return (players[index] as AudioStreamPlayer).playing

func _test_throw_blade() -> void:
	await _reset()
	_equip([RED_BLADE])
	await _tap(&"use_red_tool")
	await _frames(2)
	var projs := _projectiles()
	_eq("blade: one projectile per use", projs.size(), 1)
	if projs.is_empty():
		return
	var p = projs[0]
	_eq("blade: velocity (20 u/s = 320 px/s, right)", p.velocity, Vector2(320.0, 0.0))
	_eq("blade: damage 3 (ThrowBladeProj)", p.damage, 3)
	_eq("blade: layer PlayerAttack (8), mask Ground + Enemy (5)", [p.collision_layer, p.collision_mask], [8, 5])
	_eq("blade: max bounce 0, lifetime 10 s", [p.max_bounce, p.lifetime], [0, 10.0])
	_near("blade: spawns at the player's position (<= 3 ticks of flight)", p.global_position.x - player.global_position.x, 8.0, 8.5)
	var x0: float = p.global_position.x
	await _frames(6)
	_near("blade: measured speed over 6 ticks (px/s)", (p.global_position.x - x0) / (6.0 / FPS), 320.0, 1.0)
	_near("blade: no vertical drift", p.global_position.y - player.global_position.y, 0.0, 1.0)
	_eq("blade: charge 10 -> 9", gs.red_tools_current_charge[RED_BLADE], 9.0)
	_check("blade: throwing sound", _sound_playing(SOUND_THROWING))
	_check("blade: tool timer restarted", player.tool_timer < 0.3)
	_eq("blade: player not hurt by its own projectile", gs.current_hp, gs.max_hp)
	_clear_projectiles()
	# Facing left (Unity: localScale.x negated, velocity (-20, 0)).
	player.is_facing_left = true
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(2)
	projs = _projectiles()
	_eq("blade left: one projectile", projs.size(), 1)
	if not projs.is_empty():
		p = projs[0]
		_eq("blade left: velocity (-320, 0)", p.velocity, Vector2(-320.0, 0.0))
		_check("blade left: sprite and collider mirrored", p.get_node("Sprite2D").scale.x < 0.0 and p.get_node("Shape").position.x < 0.0)
		_check("blade left: collider 25.1 x 10.4 px, sprite scale 0.375", absf((p.get_node("Shape").shape.size.x) - 25.118) < 0.01 and absf(absf(p.get_node("Sprite2D").scale.x) - 0.375) < 0.0001)
	_clear_projectiles()
	# Hit an enemy.
	await _reset()
	_equip([RED_BLADE])
	_spawn_dummy(Vector2(64.0, DUMMY_REST_Y))
	await _frames(10)
	var hp0: int = dummy.current_hp
	await _tap(&"use_red_tool")
	var f: int = await _wait_until(func() -> bool: return dummy.current_hp < hp0, 60)
	_eq("blade hit: enemy hp -3", hp0 - dummy.current_hp, 3)
	_check("blade hit: after %d ticks (64 px away at 320 px/s)" % f, f > 8 and f < 20)
	projs = _projectiles()
	if not projs.is_empty():
		p = projs[0]
		_check("blade hit: projectile is dead (gravity 1, fading)", p.is_dead and p.gravity_scale == 1.0)
		_eq("blade hit: hit exactly one enemy", p.hit_enemies.size(), 1)
	_check("blade hit: enemy knocked away (impulse 16 px/s)", dummy.velocity.x > 0.0 and dummy.velocity.x <= 16.5)
	_eq("blade hit: silk is not gained (only melee gives silk)", gs.current_silk, 0)
	# Direct damage check on a stationary enemy (no flight): spawn the projectile on top of the dummy.
	await _reset()
	_spawn_dummy(Vector2(0.0, DUMMY_REST_Y))
	player.global_position = Vector2(-200.0, REST_Y)
	await _frames(10)
	hp0 = dummy.current_hp
	var blade := (load(BLADE_PATH) as PackedScene).instantiate()
	root.add_child(blade)
	blade.global_position = dummy.global_position
	await _frames(3)
	_eq("blade on enemy: -3 hp, dies on contact", [hp0 - dummy.current_hp, blade.is_dead], [3, true])

func _test_triple_knife() -> void:
	await _reset()
	_equip([RED_KNIFE])
	await _tap(&"use_red_tool")
	await _frames(1)
	var projs := _projectiles()
	_eq("knife: 3 projectiles per use", projs.size(), 3)
	if projs.size() == 3:
		var rad: float = deg_to_rad(10.0)
		_eq("knife: straight (320, 0)", projs[0].velocity, Vector2(320.0, 0.0))
		_near("knife: fan +10 deg (up) vx", projs[1].velocity.x, 320.0 * cos(rad), 0.01)
		_near("knife: fan +10 deg (up) vy (px/s, up = negative)", projs[1].velocity.y, -320.0 * sin(rad), 0.01)
		_near("knife: fan -10 deg (down) vy", projs[2].velocity.y, 320.0 * sin(rad), 0.01)
		_near("knife: all at 20 u/s = 320 px/s", projs[1].velocity.length(), 320.0, 0.01)
		_eq("knife: damage 1 each", [projs[0].damage, projs[1].damage, projs[2].damage], [1, 1, 1])
		_check("knife: sprite scale 0.25 (blade 0.375)", absf(projs[0].get_node("Sprite2D").scale.x - 0.25) < 0.0001)
	_eq("knife: charge 5 -> 4 (one charge for all three)", gs.red_tools_current_charge[RED_KNIFE], 4.0)
	_check("knife: throwing sound", _sound_playing(SOUND_THROWING))
	_clear_projectiles()
	player.is_facing_left = true
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(1)
	projs = _projectiles()
	if projs.size() == 3:
		var rad2: float = deg_to_rad(10.0)
		_eq("knife left: straight (-320, 0)", projs[0].velocity, Vector2(-320.0, 0.0))
		_near("knife left: point-reflected fan, 2nd goes down-left (vy +)", projs[1].velocity.y, 320.0 * sin(rad2), 0.01)
		_near("knife left: 3rd goes up-left (vy -)", projs[2].velocity.y, -320.0 * sin(rad2), 0.01)
		_check("knife left: all mirrored", projs[0].get_node("Sprite2D").scale.x < 0.0 and projs[2].get_node("Sprite2D").scale.x < 0.0)
	_clear_projectiles()
	# Damage: three knives on one enemy in the same tick = 1 damage (enemy i-frame 0.05 s, as Unity).
	await _reset()
	_spawn_dummy(Vector2(0.0, DUMMY_REST_Y))
	player.global_position = Vector2(-200.0, REST_Y)
	await _frames(10)
	var hp0: int = dummy.current_hp
	for i in 3:
		var knife := (load(KNIFE_PATH) as PackedScene).instantiate()
		root.add_child(knife)
		knife.global_position = dummy.global_position + Vector2(0.0, 9.5) # the dummy body is offset by 9.5 px
	await _frames(8)
	_eq("knife on enemy: 3 knives in one tick -> hp -1 (i-frames)", hp0 - dummy.current_hp, 1)
	# Flight hit: one knife straight at a dummy.
	await _reset()
	_equip([RED_KNIFE])
	_spawn_dummy(Vector2(48.0, DUMMY_REST_Y))
	await _frames(10)
	hp0 = dummy.current_hp
	await _tap(&"use_red_tool")
	await _wait_until(func() -> bool: return dummy.current_hp < hp0, 60)
	_check("knife flight: enemy hit for 1..3 total", hp0 - dummy.current_hp >= 1 and hp0 - dummy.current_hp <= 3)
	await _frames(20)
	_check("knife flight: damage is whole knife hits (1 each)", (hp0 - dummy.current_hp) >= 1)

func _test_charges_and_zero() -> void:
	await _reset()
	_equip([RED_BLADE])
	gs.red_tools_current_charge[RED_BLADE] = 1.0
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("charges: last charge 1 -> 0, projectile fired", [gs.red_tools_current_charge[RED_BLADE], _projectiles().size()], [0.0, 1])
	_clear_projectiles()
	await _frames(30) # past the cooldown
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("charges: no use at 0 charge (no projectile, charge stays 0)", [_projectiles().size(), gs.red_tools_current_charge[RED_BLADE]], [0, 0.0])
	_check("charges: the press still restarted the tool timer (Unity resets before the tool checks)", player.tool_timer < 0.2)
	await _reset()
	_equip([RED_KNIFE])
	gs.red_tools_current_charge[RED_KNIFE] = 0.0
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("charges: knife at 0 -> nothing", _projectiles().size(), 0)
	await _reset()
	_check("charges: nothing equipped -> V does nothing", await (func() -> bool:
		await _tap(&"use_red_tool")
		await _frames(2)
		return _projectiles().is_empty() and gs.red_tools_current_charge == [10.0, 5.0, 2.0]).call())
	await _reset()
	_equip([RED_KNIFE, RED_BLADE], 1)
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("charges: only the selected tool is used (knife selected -> 3 knives)", _projectiles().size(), 3)

func _test_cooldown() -> void:
	await _reset()
	_equip([RED_BLADE])
	_eq("cooldown value (PlayerData.toolCooldown)", gs.tool_cooldown, 0.35)
	await _tap(&"use_red_tool")
	await _frames(17) # ~0.30 s after the first press
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("cooldown: second press at ~0.30 s ignored", [_projectiles().size(), gs.red_tools_current_charge[RED_BLADE]], [1, 9.0])
	await _frames(3) # ~0.38 s after the first press
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("cooldown: press at ~0.38 s accepted", [_projectiles().size(), gs.red_tools_current_charge[RED_BLADE]], [2, 8.0])

func _test_gating() -> void:
	var blockers: Array = [
		["in_attack", "in_attack"], ["control_lock", "control_lock"], ["is_dashing", "is_dashing"],
		["in_silk_skill", "in_silk_skill"], ["resting", "resting"], ["in_menu", "in_menu"],
		["tool_anim_lock", "tool_anim_lock"], ["is_paralyzed", "is_paralyzed"], ["is_parrying", "is_parrying"],
	]
	for entry: Array in blockers:
		await _reset()
		_equip([RED_BLADE])
		var prop: String = entry[1]
		var cleared = player.get(prop)
		player.set(prop, 1 if prop == "control_lock" else true)
		player.tool_timer = 10.0
		await _tap(&"use_red_tool")
		await _frames(2)
		var blocked: bool = _projectiles().is_empty() and gs.red_tools_current_charge[RED_BLADE] == 10.0
		player.set(prop, cleared)
		await _frames(2)
		_check("gate: no tool use while %s" % entry[0], blocked)
	await _reset()
	_equip([RED_BLADE])
	player.in_attack = true
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(2)
	player.in_attack = false
	_check("gate: attack animation blocks the tool", _projectiles().is_empty())

func _test_lifeblood_needle() -> void:
	await _reset()
	_equip([RED_NEEDLE])
	gs.lifeblood_hp = 0
	await _tap(&"use_red_tool")
	await _frames(1)
	_eq("needle: charge 2 -> 1 at the press", gs.red_tools_current_charge[RED_NEEDLE], 1.0)
	_eq("needle: no projectile", _projectiles().size(), 0)
	_check("needle: lifeblood_needle clip plays", player.anim.current_animation == &"lifeblood_needle")
	_check("needle: throwing sound at the press", _sound_playing(SOUND_THROWING))
	await _frames(2)
	_check("needle: BeginToolAnimLock (lock, velocity 0, gravity off)", player.tool_anim_lock and player.velocity == Vector2.ZERO and not player.gravity_on)
	_eq("needle: lifeblood still 0 before the 0.25 s event", gs.lifeblood_hp, 0)
	var f: int = await _wait_until(func() -> bool: return gs.lifeblood_hp > 0, 40)
	_eq("needle: +2 lifeblood", gs.lifeblood_hp, 2)
	_near("needle: effect at ~0.25 s after the press (s)", (f + 3) / FPS, 0.25, 0.05)
	_check("needle: syringe sound", _sound_playing(SOUND_SYRINGE))
	var tint: Color = player.get("_flash_material").get_shader_parameter("flash_tint")
	_check("needle: FlashBlue (flash tint (0, 0.5, 1) while flashing)", tint.is_equal_approx(Color(0.0, 0.5, 1.0)))
	var fx_count := 0
	for n in root.get_children():
		if n is CPUParticles2D and n.name == "LifebloodNeedlePE":
			fx_count += 1
	_eq("needle: lifeblood splash effect spawned", fx_count, 1)
	_check("needle: still locked right after the effect", player.tool_anim_lock)
	var g: int = await _wait_until(func() -> bool: return not player.tool_anim_lock, 60)
	_near("needle: EndToolAnimLock at ~0.5833 s after the press (s)", (f + 3 + g) / FPS, 0.5833, 0.05)
	_check("needle: gravity back on", player.gravity_on)
	await _frames(12)
	var tint2: Color = player.get("_flash_material").get_shader_parameter("flash_tint")
	_check("needle: flash tint restored to white", tint2.is_equal_approx(Color.WHITE))
	_eq("needle: HUD data: lifeblood 2", gs.lifeblood_hp, 2)

	# Not usable while lifeblood is left.
	_clear_projectiles()
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(3)
	_eq("needle gate: lifeblood > 0 -> no use, charge stays 1", [gs.red_tools_current_charge[RED_NEEDLE], player.tool_anim_lock], [1.0, false])
	# Lifeblood gone, charge available again -> works; charge 0 -> not.
	gs.lifeblood_hp = 0
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("needle: second use (charge 1 -> 0)", gs.red_tools_current_charge[RED_NEEDLE], 0.0)
	await _frames(45)
	_eq("needle: second use grants 2 more lifeblood", gs.lifeblood_hp, 2)
	gs.lifeblood_hp = 0
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(3)
	_eq("needle gate: charge 0 -> nothing (no lock, no lifeblood)", [player.tool_anim_lock, gs.lifeblood_hp], [false, 0])
	# Damage during the lock releases it (Unity Damaged: toolAnimLock = false).
	await _reset()
	_equip([RED_NEEDLE])
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(5)
	_check("needle: locked mid-clip", player.tool_anim_lock)
	player.damaged(1, Vector2.RIGHT)
	_check("needle: damage releases the lock and gravity", not player.tool_anim_lock and player.gravity_on)
	await _frames(60)

func _test_swap_key() -> void:
	await _reset()
	_equip([RED_BLADE, RED_KNIFE], 1)
	await _tap(&"swap_tool_right")
	await _frames(1)
	_eq("swap key: E selects the next tool", gs.selected_red_tool_id, 1)
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(2)
	_eq("swap key: the swapped-to tool (knife) is used", _projectiles().size(), 3)
	_clear_projectiles()
	await _tap(&"swap_tool_right")
	await _frames(1)
	_eq("swap key: wraps to 0", gs.selected_red_tool_id, 0)
	await _reset()
	player.in_menu = true
	_equip([RED_BLADE, RED_KNIFE], 1)
	await _tap(&"swap_tool_right")
	await _frames(2)
	_eq("swap key: ignored while in a menu", gs.selected_red_tool_id, 0)

func _test_chair_refill() -> void:
	await _reset()
	gs.red_tools_current_charge.assign([3.0, 1.0, 0.0])
	var chair := (load(CHAIR_PATH) as PackedScene).instantiate()
	root.add_child(chair)
	chair.global_position = Vector2(0, REST_Y)
	await _frames(2)
	chair.get_on_chair()
	_eq("chair: sitting refills every red tool (maxCharge 10 / 5 / 2)", gs.red_tools_current_charge, [10.0, 5.0, 2.0])
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://player.json"))
	_eq("chair: the refill is in the save written by the sit", saved["red_tools_current_charge"], [10.0, 5.0, 2.0])
	_equip([RED_BLADE])
	player.tool_timer = 10.0
	await _tap(&"use_red_tool")
	await _frames(2)
	_check("chair: resting blocks tool use", _projectiles().is_empty())
	chair._get_off_chair()
	chair.free()
	player.resting = false
	gs.delete_save()


# --- part 3: world ---

func _boot_world() -> void:
	gs.reset_to_new_game()
	world = (load(WORLD_PATH) as PackedScene).instantiate()
	world.spawn_debug_dummies = false
	world.set("start_mode", NEW_GAME)
	root.add_child(world)
	current_scene = world
	player = world.get_node("Player")
	gm = world.get_node("GameMenu")
	hud = world.get_node("HUD")
	await _wait_until(func() -> bool: return not rl.is_transitioning(), 900)
	await _wait_until(func() -> bool: return player.is_on_floor(), 600)
	await _frames(5)
	player.tool_timer = 10.0

func _focus_name() -> String:
	var f := root.gui_get_focus_owner()
	return f.name if f != null else "<none>"

func _open_tools_tab() -> void:
	if gm.is_open():
		gm.close(true)
		await _frames(3)
	await _key(KEY_I)
	await _frames(3)

func _close_menu() -> void:
	if gm.is_open():
		gm.close(true)
	await _frames(3)

func _page():
	return gm.pages[TAB_TALISMAN]

func _test_debug_grant() -> void:
	gs.reset_to_new_game()
	await _key(KEY_F8)
	_eq("F8: found talismans (Wanderer, Sentinel)", gs.found_talismans, [0, 1])
	_eq("F8: found red / blue / yellow tools", [gs.found_red_tools, gs.found_blue_tools, gs.found_yellow_tools], [[0, 1, 2], [0, 1], [0]])
	await _key(KEY_F8)
	_eq("F8: idempotent", gs.found_red_tools, [0, 1, 2])

func _test_tab_not_resting() -> void:
	await _open_tools_tab()
	var page = _page()
	_eq("tab: opens on the Tools tab", gm.current_tab, TAB_TALISMAN)
	_check("tab: Talisman page visible", page.visible)
	_eq("tab: first red tool button focused", _focus_name(), "ThrowBlade")
	_eq("tab: info box shows the focused tool", [page.info_name.text, page.info_image.visible], ["Throw Blade", true])
	_eq("tab: info description", page.info_desc.text, "A thick and short blade for throwing. Made from hard steel.")
	_check("tab: reminder shown while not resting", page.reminder.visible)
	_eq("tab: Wanderer crest slots red / blue / yellow", [page.red_slots.size(), page.blue_slots.size(), page.yellow_slots.size()], [1, 1, 1])
	_eq("tab: crest name label", page.talisman_name_label.text, "WANDERER")
	_check("tab: crest sprite is the Wanderer crest", page.crest.texture.resource_path.ends_with("TalismanWanderer.png"))
	_check("tab: crest tint (0.368 grey)", absf(page.crest.modulate.r - 0.3679245) < 0.001)
	_check("tab: found tools show their sprites", page.red_buttons[0].icon_rect.texture.resource_path.ends_with("ThrowBlade.png")
			and page.blue_buttons[1].icon_rect.texture.resource_path.ends_with("WeaverMask.png")
			and page.yellow_buttons[0].icon_rect.texture.resource_path.ends_with("CrabOrb.png"))
	_check("tab: select frame shown on the focused button only", page.red_buttons[0].is_frame_visible() and not page.red_buttons[1].is_frame_visible())
	page.red_buttons[1].grab_focus()
	_check("tab: moving sound played on focus change", gm.get_node("Sfx/Moving").playing)
	page.red_buttons[0].grab_focus()
	await _frames(2)
	# Navigation.
	await _key(KEY_RIGHT)
	_eq("tab: Right -> Triple Knife", [_focus_name(), page.info_name.text], ["TripleKnife", "Triple Knife"])
	await _key(KEY_RIGHT)
	_eq("tab: Right -> Lifeblood Needle", _focus_name(), "LifebloodNeedle")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	await _key(KEY_DOWN)
	_eq("tab: Down from the first red tool -> Acid Orb", _focus_name(), "AcidOrb")
	await _key(KEY_DOWN)
	_eq("tab: Down -> Crab Orb", _focus_name(), "CrabOrb")
	await _key(KEY_UP)
	await _key(KEY_UP)
	_eq("tab: back to Throw Blade", _focus_name(), "ThrowBlade")
	await _key(KEY_LEFT)
	_eq("tab: Left from the first column -> Change Talisman", _focus_name(), "ChangeTalisman")
	_check("tab: change button frame visible", page.change_frame.visible)
	# Not resting: nothing can be equipped or changed.
	gm.get_node("Sfx/Pressed").stop()
	await _key(KEY_ENTER)
	_eq("not resting: Change Talisman does nothing", [gs.equipped_talisman, gm.get_node("Sfx/Pressed").playing], [0, false])
	await _key(KEY_RIGHT)
	_check("not resting: Right from Change Talisman moves the focus", _focus_name() != "ChangeTalisman" and _focus_name() != "<none>")
	page.red_buttons[0].grab_focus()
	await _frames(2)
	await _key(KEY_ENTER)
	_eq("not resting: equip refused", [gs.equipped_red_tools, gm.get_node("Sfx/Pressed").playing], [[], false])
	_check("not resting: not equipped tool has full alpha", page.red_buttons[0].icon_rect.modulate.a == 1.0)
	await _close_menu()

func _test_tab_resting() -> void:
	player.resting = true
	await _open_tools_tab()
	var page = _page()
	_check("resting: reminder hidden", not page.reminder.visible)
	page.red_buttons[0].grab_focus()
	await _frames(2)
	await _key(KEY_ENTER)
	_eq("resting: Enter equips Throw Blade", gs.equipped_red_tools, [0])
	_check("resting: pressed sound", gm.get_node("Sfx/Pressed").playing)
	_check("resting: equipped icon alpha 0.3", is_equal_approx(page.red_buttons[0].icon_rect.modulate.a, 0.3))
	_check("resting: other tools stay at alpha 1", page.red_buttons[1].icon_rect.modulate.a == 1.0)
	_check("resting: crest red slot shows the tool", page.red_slots[0].get_node("Image").visible
			and page.red_slots[0].get_node("Image").texture.resource_path.ends_with("ThrowBlade.png"))
	_check("resting: blue / yellow slot images hidden", not page.blue_slots[0].get_node("Image").visible and not page.yellow_slots[0].get_node("Image").visible)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_eq("resting: second red tool refused (Wanderer has 1 red slot)", gs.equipped_red_tools, [0])
	_check("resting: refused tool stays at alpha 1", page.red_buttons[1].icon_rect.modulate.a == 1.0)
	# Blue and yellow (display / equip only).
	await _key(KEY_LEFT)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_eq("resting: Acid Orb equips into the blue slot", gs.equipped_blue_tools, [0])
	_check("resting: blue slot image", page.blue_slots[0].get_node("Image").visible
			and page.blue_slots[0].get_node("Image").texture.resource_path.ends_with("AcidOrb.png"))
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_eq("resting: Crab Orb equips into the yellow slot", gs.equipped_yellow_tools, [0])
	# Unequip.
	await _key(KEY_ENTER)
	_eq("resting: pressing an equipped tool unequips it", gs.equipped_yellow_tools, [])
	_check("resting: yellow slot image hidden again, icon alpha 1", not page.yellow_slots[0].get_node("Image").visible
			and page.yellow_buttons[0].icon_rect.modulate.a == 1.0)
	# Change talisman.
	page.change_button.grab_focus()
	await _frames(2)
	gm.get_node("Sfx/Pressed").stop()
	await _key(KEY_ENTER)
	_eq("change: Wanderer -> Sentinel", gs.equipped_talisman, 1)
	_eq("change: all tools unequipped", [gs.equipped_red_tools, gs.equipped_blue_tools, gs.equipped_yellow_tools], [[], [], []])
	_check("change: pressed sound", gm.get_node("Sfx/Pressed").playing)
	_eq("change: Sentinel crest slots red / blue / yellow", [page.red_slots.size(), page.blue_slots.size(), page.yellow_slots.size()], [2, 2, 0])
	_eq("change: crest name", page.talisman_name_label.text, "SENTINEL")
	_check("change: crest sprite", page.crest.texture.resource_path.ends_with("TalismanSentinel.png"))
	_check("change: tool buttons back to alpha 1", page.red_buttons[0].icon_rect.modulate.a == 1.0 and page.blue_buttons[0].icon_rect.modulate.a == 1.0)
	# Sentinel: two reds.
	page.red_buttons[0].grab_focus()
	await _frames(2)
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_eq("Sentinel: two red tools equip, the third is refused", gs.equipped_red_tools, [0, 1])
	_check("Sentinel: both red slots show icons in order", page.red_slots[0].get_node("Image").texture.resource_path.ends_with("ThrowBlade.png")
			and page.red_slots[1].get_node("Image").texture.resource_path.ends_with("TripleKnife.png"))
	# Change again wraps back to the Wanderer and unequips.
	page.change_button.grab_focus()
	await _frames(2)
	await _key(KEY_ENTER)
	_eq("change: Sentinel -> Wanderer wraps, tools cleared", [gs.equipped_talisman, gs.equipped_red_tools], [0, []])
	# The page re-reads the data when it is shown again.
	gs.equipped_talisman = 1
	gs.equipped_red_tools.assign([2])
	gs.equipped_blue_tools.assign([1])
	await _close_menu()
	await _open_tools_tab()
	_eq("reopen: crest follows GameState (Sentinel)", [page.red_slots.size(), page.talisman_name_label.text], [2, "SENTINEL"])
	_check("reopen: equipped icons restored", page.red_slots[0].get_node("Image").texture.resource_path.ends_with("LifebloodNeedle.png")
			and is_equal_approx(page.red_buttons[2].icon_rect.modulate.a, 0.3) and is_equal_approx(page.blue_buttons[1].icon_rect.modulate.a, 0.3))
	await _close_menu()
	player.resting = false
	gs.equipped_talisman = 0
	gs.unequip_all_tools()

func _test_tab_unfound() -> void:
	gs.reset_to_new_game()
	await _open_tools_tab()
	var page = _page()
	_check("unfound: tool buttons show the empty-tool sprite", page.red_buttons[0].icon_rect.texture.resource_path.ends_with("EmptyTool.png")
			and page.blue_buttons[1].icon_rect.texture.resource_path.ends_with("EmptyTool.png"))
	_eq("unfound: info box empty and image hidden", [page.info_name.text, page.info_desc.text, page.info_image.visible], ["", "", false])
	_eq("unfound: Wanderer crest from the new-game data", page.talisman_name_label.text, "WANDERER")
	player.resting = true
	await _key(KEY_ENTER)
	_eq("unfound: pressing an unfound tool does nothing", gs.equipped_red_tools, [])
	player.resting = false
	await _close_menu()

func _test_menu_blocks_tools() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	_set_list(gs.equipped_red_tools, [RED_BLADE])
	player.tool_timer = 10.0
	await _open_tools_tab()
	await _key(KEY_V)
	await _frames(2)
	_eq("menu open: V does not throw", [_projectiles().size(), gs.red_tools_current_charge[RED_BLADE]], [0, 10.0])
	await _close_menu()
	await _frames(6)

func _test_world_tool_use() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	_set_list(gs.equipped_red_tools, [RED_BLADE])
	player.tool_timer = 10.0
	await _key(KEY_V)
	await _frames(2)
	var projs := _projectiles()
	_eq("world: V throws a blade after the menu is closed", projs.size(), 1)
	if not projs.is_empty():
		_check("world: projectile lives in the current room", projs[0].get_parent() == rl.current_room)
		_eq("world: charge 10 -> 9", gs.red_tools_current_charge[RED_BLADE], 9.0)
	_clear_projectiles()
	# E in the menu switches tabs, not tools.
	_set_list(gs.equipped_red_tools, [RED_BLADE, RED_KNIFE])
	gs.equipped_talisman = 1
	gs.selected_red_tool_id = 0
	await _open_tools_tab()
	await _key(KEY_E)
	_eq("world: E in the menu changes the tab, not the tool", [gm.current_tab, gs.selected_red_tool_id], [2, 0])
	await _close_menu()
	await _frames(6)
	await _key(KEY_E)
	_eq("world: E outside the menu swaps the tool", gs.selected_red_tool_id, 1)
	await _key(KEY_E)
	_eq("world: E wraps back", gs.selected_red_tool_id, 0)

func _test_hud() -> void:
	gs.reset_to_new_game()
	gs.grant_debug_inventory()
	gs.unequip_all_tools()
	await _frames(2)
	_check("hud: tool circle hidden without equipped red tools", not hud.tool_circle.visible)
	gs.equipped_talisman = 1
	_set_list(gs.equipped_red_tools, [RED_BLADE, RED_KNIFE])
	gs.selected_red_tool_id = 0
	gs.stats_changed.emit()
	await _frames(2)
	_check("hud: tool circle visible", hud.tool_circle.visible)
	_near("hud: full charge fill 1.0 (10 / 10)", hud.tool_circle_fill.value, 1.0, 0.0001)
	_check("hud: icon is the selected tool", hud.tool_circle_icon.texture.resource_path.ends_with("ThrowBlade.png"))
	gs.consume_red_tool_charge(RED_BLADE)
	gs.consume_red_tool_charge(RED_BLADE)
	gs.consume_red_tool_charge(RED_BLADE)
	_near("hud: after 3 throws fill 0.7", hud.tool_circle_fill.value, 0.7, 0.0001)
	gs.swap_tool(true)
	_near("hud: swapped to Triple Knife (5 / 5) fill 1.0", hud.tool_circle_fill.value, 1.0, 0.0001)
	_check("hud: icon follows the swap", hud.tool_circle_icon.texture.resource_path.ends_with("TripleKnife.png"))
	gs.red_tools_current_charge[RED_KNIFE] = 2.0
	gs.stats_changed.emit()
	_near("hud: knife 2 / 5 -> 0.4", hud.tool_circle_fill.value, 0.4, 0.0001)
	_set_list(gs.equipped_red_tools, [RED_NEEDLE])
	gs.selected_red_tool_id = 0
	gs.red_tools_current_charge[RED_NEEDLE] = 1.0
	gs.stats_changed.emit()
	_near("hud: needle 1 / 2 -> 0.5", hud.tool_circle_fill.value, 0.5, 0.0001)
	gs.red_tools_current_charge[RED_NEEDLE] = 0.0
	gs.stats_changed.emit()
	_near("hud: 0 charge -> 0 fill", hud.tool_circle_fill.value, 0.0, 0.0001)
	_eq("hud: radial fill starts at the bottom (180 deg), full circle, clockwise", [hud.tool_circle_fill.radial_initial_angle, hud.tool_circle_fill.radial_fill_degrees, hud.tool_circle_fill.fill_mode], [180.0, 360.0, TextureProgressBar.FILL_CLOCKWISE])
	gs.refill_red_tools()
	_near("hud: refill -> full again", hud.tool_circle_fill.value, 1.0, 0.0001)
	# Using a tool through the player updates the HUD.
	_set_list(gs.equipped_red_tools, [RED_BLADE])
	gs.selected_red_tool_id = 0
	gs.stats_changed.emit()
	player.tool_timer = 10.0
	await _key(KEY_V)
	await _frames(2)
	_near("hud: a real throw lowers the circle to 0.9", hud.tool_circle_fill.value, 0.9, 0.0001)
	_clear_projectiles()


func _print_table() -> void:
	print("")
	print("%-76s | %-34s | %-30s | %s" % ["Check", "Measured", "Expected", "Result"])
	print("-".repeat(160))
	for r in rows:
		print("%-76s | %-34s | %-30s | %s %s" % [str(r[0]).left(76), str(r[1]).left(34), str(r[2]).left(30), r[3], r[4]])
	print("")
	print("%s  (%d checks, %d failed)" % ["ALL PASS" if fails == 0 else "FAILURES", rows.size(), fails])
