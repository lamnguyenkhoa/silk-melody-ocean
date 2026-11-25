class_name SceneFlow
extends RefCounted
## Scene switching between the main menu and the world (the rooms themselves are swapped by RoomLoader).
## Done by hand instead of SceneTree.change_scene_to_file so it also works when the scene was added to
## the root without being the "current scene" (tests) and so the new scene can be configured (start
## mode) before it enters the tree.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Replace [param old] (the menu) by a fresh World that boots with [param mode].
static func to_world(tree: SceneTree, mode: RoomLoader.StartMode, old: Node) -> World:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	world.start_mode = mode
	_swap(tree, world, old)
	return world

## Replace [param old] (the world) by a fresh main menu. Clears pause / hit-stop time scale first so the
## menu never inherits them.
static func to_main_menu(tree: SceneTree, old: Node) -> Node:
	tree.paused = false
	Engine.time_scale = 1.0
	var menu := (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	_swap(tree, menu, old)
	return menu

static func _swap(tree: SceneTree, new_scene: Node, old: Node) -> void:
	tree.root.add_child(new_scene)
	tree.current_scene = new_scene
	if old != null and is_instance_valid(old):
		old.queue_free()
