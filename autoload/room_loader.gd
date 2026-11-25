extends Node
## Port of LevelLoader.cs (+ the call side of ChangeLevelTrigger.cs), plan 7.2.
## The persistent World scene registers itself (register_world); rooms are swapped under
## World/RoomContainer. Unity reloads scenes and keeps the player alive with DontDestroyOnLoad;
## here the player node simply stays where it is and is moved (it is never freed).

## How the world boots (MainMenu New Game / Continue buttons).
enum StartMode {
	## GameMaster.InitNewGameData() and DirtCave0; an existing save is left on disk untouched.
	NEW_GAME,
	## SaveSystem.LoadPlayerData() and the saved respawn scene (falls back to a new game without a save).
	CONTINUE,
}

## Emitted after a room was instanced and the player placed (also on boot).
signal room_loaded(room: Node, room_name: String)

const ROOM_DIR := "res://scenes/rooms/"
## First scene of a new game (MainMenu.NewGameButton loads "DirtCave0").
const START_ROOM := "DirtCave0"

## Unity: LevelLoader.transitionTime, seconds (fade-out length and wait before the swap).
var transition_time: float = 1.0
## Name of the loaded room ("DirtCave3" = Unity scene name = room root node name).
var current_room_name: String = ""
var current_room: Node

var world: Node2D
var player: Player
var camera: GameCamera
var fader: Fader
var room_container: Node2D

## Unity: LevelLoader.doRespawn.
var _do_respawn: bool = false
## Unity: LevelLoader.spawnPosName.
var _spawn_name: String = ""
## Generation counter: a newer load_level supersedes an older in-flight one.
var _load_id: int = 0
## Generation of the load (boot or room transition) that is currently running; 0 = none.
var _transition_owner: int = 0

## Called by World._ready.
func register_world(w: Node2D, p: Player, cam: GameCamera, f: Fader, container: Node2D) -> void:
	world = w
	player = p
	camera = cam
	fader = f
	room_container = container

## Called by World._exit_tree: drops every reference and invalidates in-flight loads.
func unregister_world(w: Node2D) -> void:
	if world != w:
		return
	_load_id += 1
	_transition_owner = 0
	_do_respawn = false
	_spawn_name = ""
	world = null
	player = null
	camera = null
	fader = null
	room_container = null
	current_room = null
	current_room_name = ""

## True while a boot or a room transition (fade out, swap) is running; the pause menu is refused then.
func is_transitioning() -> bool:
	return _transition_owner != 0

func is_ready_to_load() -> bool:
	return world != null and is_instance_valid(world) and player != null and room_container != null

## SceneManager scene name -> res path: "DirtCave0" -> res://scenes/rooms/dirt_cave_0.tscn.
static func room_path(room_name: String) -> String:
	return ROOM_DIR + snake_case(room_name) + ".tscn"

## Word-boundary snake_case that also splits letter/digit ("DirtCave14" -> "dirt_cave_14").
static func snake_case(text: String) -> String:
	var out: String = ""
	for i in text.length():
		var c: String = text[i]
		var is_upper: bool = c != c.to_lower()
		var is_digit: bool = c >= "0" and c <= "9"
		if i > 0:
			var prev: String = text[i - 1]
			var prev_digit: bool = prev >= "0" and prev <= "9"
			if (is_upper or is_digit) and not prev_digit and prev != "_":
				out += "_"
		out += c.to_lower()
	return out

## Boot (LevelLoader.Awake + SpawnPointInit, plus the MainMenu buttons): NEW_GAME resets GameState to
## the new-game defaults, CONTINUE loads the save on disk; then loads respawn_scene and places the
## player on the chair / respawn position. Synchronous (no fade).
func start(mode: StartMode) -> void:
	if not is_ready_to_load():
		push_warning("RoomLoader.start: no world registered")
		return
	_load_id += 1
	var my_id: int = _load_id
	_transition_owner = my_id
	var continue_game: bool = mode == StartMode.CONTINUE
	if continue_game and not GameState.save_exists():
		push_warning("RoomLoader.start: CONTINUE without a save, starting a new game")
		continue_game = false
	if continue_game:
		GameState.load_save()
	else:
		GameState.reset_to_new_game()
	player.dash_count = GameState.max_dash
	player.jump_count = GameState.extra_jump
	var room_name: String = GameState.respawn_scene if GameState.respawn_scene != "" else START_ROOM
	_do_respawn = true
	_spawn_name = ""
	await _swap_room(room_name, true, my_id)
	if _transition_owner == my_id:
		_transition_owner = 0

## LevelLoader.LoadLevel: lock the player, fade out, swap the room, place the player, fade in.
func load_level(room_name: String, spawn_name: String) -> void:
	if not is_ready_to_load():
		return # no World scene (standalone player in unit tests): nothing to load
	_load_id += 1
	var my_id: int = _load_id
	_spawn_name = spawn_name
	_transition_owner = my_id
	player.control_lock += 1
	player.gravity_on = false
	fader.fade_out(transition_time)
	# Pausable timer (process_always = false): the pause menu is blocked during transitions anyway.
	await get_tree().create_timer(transition_time, false, true).timeout
	if my_id != _load_id or not is_ready_to_load():
		# Superseded by a newer load (e.g. death during a transition): only undo our lock.
		if player != null and is_instance_valid(player):
			player.control_lock = maxi(player.control_lock - 1, 0)
		return
	await _swap_room(room_name, false, my_id)
	if _transition_owner == my_id:
		_transition_owner = 0
	if my_id == _load_id and is_ready_to_load():
		fader.fade_in(transition_time)

## LevelLoader.Respawn.
func respawn() -> void:
	if not is_ready_to_load():
		return
	_do_respawn = true
	load_level(GameState.respawn_scene, "")

## LevelLoader.UpdateSpawnPoint (called by the rest chair).
func update_spawn_point(chair_name: String) -> void:
	GameState.respawn_chair_name = chair_name
	GameState.respawn_scene = current_room_name

## Frees the old room, instances the new one and runs UpdatePlayerPosition. Returns false (and
## releases the player) if the room scene does not exist.
## The player is moved BEFORE the new room enters the tree: otherwise a trigger of the new room that
## overlaps the player's old position (e.g. the same exit area in the previous room) would queue a
## body_entered for the stale position and fire an unwanted transition.
func _swap_room(room_name: String, boot: bool, my_id: int) -> bool:
	var path: String = room_path(room_name)
	if not ResourceLoader.exists(path):
		push_error("RoomLoader: room scene not found: %s" % path)
		_do_respawn = false
		player.gravity_on = true
		if not boot:
			player.control_lock = maxi(player.control_lock - 1, 0)
		return false
	if current_room != null and is_instance_valid(current_room):
		current_room.get_parent().remove_child(current_room)
		current_room.queue_free()
	var room: Node = (load(path) as PackedScene).instantiate()
	current_room = room
	current_room_name = room_name
	if boot and GameState.respawn_chair_name == "" and GameState.respawn_pos == Vector2.ZERO:
		# SpawnPointInit edge case: new game, died before the first chair.
		var start_marker := room.get_node_or_null("PlayerStart") as Node2D
		if start_marker != null:
			GameState.respawn_pos = _room_point(room, start_marker)
	var chair: Node = _update_player_position(room)
	# A CharacterBody2D (kinematic) only applies its new transform to the physics server on the next
	# physics step; wait for it so triggers / contact areas of the new room are created against the
	# NEW position, not the stale one.
	player.force_update_transform()
	await get_tree().physics_frame
	if my_id != _load_id or not is_ready_to_load():
		# The world was freed (back to the main menu) or a newer load took over while waiting.
		room.free()
		if not boot and player != null and is_instance_valid(player):
			player.control_lock = maxi(player.control_lock - 1, 0)
		return false
	room_container.add_child(room)
	if "current_room" in world:
		world.set("current_room", room)
	GameState.add_visited_room(room_name)
	# Make the new collision shapes exist before the player starts moving next to them.
	for child in room.get_children():
		if child is TileMapLayer:
			(child as TileMapLayer).update_internals()
	if chair != null:
		chair.call("get_on_chair")
	player.gravity_on = true
	camera.set_room_limits(room)
	camera.snap_to_target()
	if not boot:
		# Unity: disableControlCounter -= 1 on every scene load, clamped to 0.
		player.control_lock = maxi(player.control_lock - 1, 0)
	room_loaded.emit(room, room_name)
	return true

## World position of [param node] inside a room that is not in the tree yet.
func _room_point(room: Node, node: Node2D) -> Vector2:
	var p: Vector2 = Vector2.ZERO
	var n: Node = node
	while n is Node2D:
		p = (n as Node2D).transform * p
		if n == room:
			break
		n = n.get_parent()
	return room_container.global_transform * p

## LevelLoader.UpdatePlayerPosition (control-lock decrement is done by the caller). Returns the
## respawn chair when the player has to sit on one once the room is in the tree.
func _update_player_position(room: Node) -> Node:
	var chair_to_sit: Node = null
	if _do_respawn:
		_do_respawn = false
		var chair: Node2D = null
		if GameState.respawn_chair_name != "":
			chair = room.get_node_or_null(GameState.respawn_chair_name) as Node2D
			if chair == null:
				push_error("RoomLoader: respawn chair '%s' not found in %s" % [GameState.respawn_chair_name, room.name])
		if chair == null:
			player.global_position = GameState.respawn_pos
			player.velocity = Vector2.ZERO
			player.is_kinematic = false
		else:
			player.global_position = _room_point(room, chair)
			chair_to_sit = chair
	elif _spawn_name != "":
		var target := room.get_node_or_null(_spawn_name) as Node2D
		if target == null:
			target = room.find_child(_spawn_name, true, false) as Node2D
		if target == null:
			push_error("RoomLoader: spawn point '%s' not found in %s" % [_spawn_name, room.name])
		else:
			player.global_position = _room_point(room, target)
	_spawn_name = ""
	return chair_to_sit
