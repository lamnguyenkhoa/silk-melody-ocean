extends SceneTree
## Builds sunnyland_tileset.tres and scenes/rooms/dirt_cave_N.tscn from tools/room_data/*.json
## (written by tools/unity_room_converter.py).
## Run: godot --headless --path . -s tools/build_rooms.gd

const DATA_DIR := "res://tools/room_data/"
const ROOM_DIR := "res://scenes/rooms/"
const TILESET_PATH := "res://scenes/rooms/sunnyland_tileset.tres"
const EXIT_SCENE := "res://scenes/interactables/room_exit.tscn"
## Enemy type (from the Unity prefab GUID) -> scene (P5; P1 emitted Marker2D placeholders).
const ENEMY_SCENES := {
	"Crawling": "res://scenes/enemies/crawling.tscn",
	"Dipsa": "res://scenes/enemies/dipsa.tscn",
	"Crabber": "res://scenes/enemies/crabber.tscn",
}
const ROOM_COUNT := 4
const TILE := 16
const GROUND_LAYER_BIT := 1 # physics layer 1 = Ground
const LAYER_Z := {"Background": -10, "Tilemap": 0, "Foreground": 10}


func _initialize() -> void:
	await process_frame # autoloads must exist before the enemy scripts compile
	var ok := _build()
	quit(0 if ok else 1)


func _read_json(path: String) -> Variant:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_error("cannot read " + path)
		return null
	return JSON.parse_string(txt)


func _build() -> bool:
	var ts_data: Dictionary = _read_json(DATA_DIR + "tileset.json")
	if ts_data.is_empty():
		return false
	var tileset := _build_tileset(ts_data)
	if ResourceSaver.save(tileset, TILESET_PATH) != OK:
		push_error("failed to save tileset")
		return false
	# Reload so that rooms reference the saved resource as an external resource.
	tileset = ResourceLoader.load(TILESET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var exit_scene: PackedScene = load(EXIT_SCENE)
	for n in ROOM_COUNT:
		var room: Dictionary = _read_json(DATA_DIR + "dirt_cave_%d.json" % n)
		if room.is_empty() or not _build_room(n, room, tileset, exit_scene):
			return false
	print("build_rooms: done")
	return true


func _build_tileset(d: Dictionary) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, GROUND_LAYER_BIT)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = load(d["texture"])
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var half := TILE / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for t: Array in d["tiles"]:
		var c := Vector2i(int(t[0]), int(t[1]))
		src.create_tile(c)
		var td: TileData = src.get_tile_data(c, 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, square)
	return ts


func _own(node: Node, root: Node) -> void:
	node.owner = root


func _build_room(n: int, d: Dictionary, tileset: TileSet, exit_scene: PackedScene) -> bool:
	var root := Node2D.new()
	root.name = "DirtCave%d" % n

	for lname: String in ["Background", "Tilemap", "Foreground"]:
		var layer := TileMapLayer.new()
		layer.name = lname
		layer.tile_set = tileset
		layer.z_index = LAYER_Z[lname]
		layer.collision_enabled = (lname == "Tilemap")
		root.add_child(layer)
		_own(layer, root)
		for c: Array in d["layers"].get(lname, []):
			if int(c[4]) != 0 or int(c[5]) != 0:
				push_error("flipped tile in %s/%s not supported by builder" % [root.name, lname])
				return false
			layer.set_cell(Vector2i(int(c[0]), int(c[1])), 0, Vector2i(int(c[2]), int(c[3])))

	for e: Dictionary in d["entries"]:
		var m := Marker2D.new()
		m.name = e["name"]
		m.position = Vector2(e["pos"][0], e["pos"][1])
		root.add_child(m)
		_own(m, root)
		m.add_to_group("spawn_points", true)

	if d["player_start"] != null:
		var ps := Marker2D.new()
		ps.name = "PlayerStart"
		ps.position = Vector2(d["player_start"]["pos"][0], d["player_start"]["pos"][1])
		root.add_child(ps)
		_own(ps, root)
		ps.add_to_group("player_start", true)

	for e: Dictionary in d["exits"]:
		var ex: Node = exit_scene.instantiate()
		ex.name = "Exit_" + String(e["name"]).replace(" ", "_")
		ex.position = Vector2(e["pos"][0], e["pos"][1])
		ex.set("level_name", e["level_name"])
		ex.set("spawn_pos_name", e["spawn_pos_name"])
		ex.set("disabled", bool(e["disabled"]))
		ex.set("box_size", Vector2(e["size"][0], e["size"][1]))
		ex.set("box_offset", Vector2(e["offset"][0], e["offset"][1]))
		root.add_child(ex)
		_own(ex, root)

	var type_counts := {}
	for e: Dictionary in d["enemies"]:
		var t: String = e["type"]
		type_counts[t] = int(type_counts.get(t, 0)) + 1
		if not ENEMY_SCENES.has(t):
			push_error("no enemy scene for type " + t)
			return false
		var m: Node2D = (load(ENEMY_SCENES[t] as String) as PackedScene).instantiate()
		m.name = t if type_counts[t] == 1 else "%s%d" % [t, type_counts[t]]
		m.position = Vector2(e["pos"][0], e["pos"][1])
		m.set_meta("enemy_type", t)
		m.set_meta("unity_name", e["unity_name"])
		root.add_child(m)
		_own(m, root)
		m.add_to_group("enemy_spawns", true)

	for c: Dictionary in d["rest_chairs"]:
		var m := Marker2D.new()
		m.name = c["name"]
		m.position = Vector2(c["pos"][0], c["pos"][1])
		root.add_child(m)
		_own(m, root)
		m.add_to_group("rest_chairs", true)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("pack failed for " + root.name)
		return false
	var path := ROOM_DIR + "dirt_cave_%d.tscn" % n
	if ResourceSaver.save(packed, path) != OK:
		push_error("save failed " + path)
		return false
	print("saved ", path)
	root.free()
	return true
