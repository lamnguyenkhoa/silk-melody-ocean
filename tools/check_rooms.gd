extends SceneTree
## Headless verification of the converted rooms.
## Run: godot --headless --path . -s tools/check_rooms.gd
## Unity m_TileIndex totals (all three tilemaps): DirtCave0 1104, DirtCave1 1903, DirtCave2 1850, DirtCave3 677.

const UNITY_TOTALS := [1104, 1903, 1850, 677]
const LAYERS := ["Background", "Tilemap", "Foreground"]

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_fail += 1


func _initialize() -> void:
	var rooms: Array[Node] = []
	for n in 4:
		var ps: PackedScene = load("res://scenes/rooms/dirt_cave_%d.tscn" % n)
		var r: Node = ps.instantiate()
		root.add_child(r)
		rooms.append(r)
	for n in 4:
		_check_room(n, rooms[n], rooms)
	print("check_rooms: ", "FAILED (%d)" % _fail if _fail > 0 else "ALL OK")
	quit(1 if _fail > 0 else 0)


func _is_solid(room: Node, p: Vector2) -> bool:
	var tm: TileMapLayer = room.get_node("Tilemap")
	return tm.get_cell_source_id(tm.local_to_map(p)) != -1


func _check_room(n: int, room: Node, rooms: Array[Node]) -> void:
	print("== %s ==" % room.name)
	var total := 0
	for l: String in LAYERS:
		var tm: TileMapLayer = room.get_node(l)
		var cnt := tm.get_used_cells().size()
		total += cnt
		print("  %s: %d tiles, z=%d, collision=%s, used_rect=%s" % [l, cnt, tm.z_index, tm.collision_enabled, tm.get_used_rect()])
	_check(total == UNITY_TOTALS[n], "tile total %d == Unity %d" % [total, UNITY_TOTALS[n]])
	_check(room.get_node("Tilemap").collision_enabled and not room.get_node("Background").collision_enabled \
		and not room.get_node("Foreground").collision_enabled, "collision only on Tilemap")
	var spawns: Dictionary = {}
	for c in room.get_children():
		if c is RoomExit:
			var e: RoomExit = c
			print("  exit %s pos=%s size=%s offset=%s -> %s/%s disabled=%s" % [e.name, e.position, e.box_size, e.box_offset, e.level_name, e.spawn_pos_name, e.disabled])
			_check(e.collision_layer == 0 and e.collision_mask == 2, "%s layer none / mask Player" % e.name)
			var cs: CollisionShape2D = e.get_node("CollisionShape2D")
			_check(cs.shape is RectangleShape2D and (cs.shape as RectangleShape2D).size == e.box_size, "%s has RectangleShape2D sized from data" % e.name)
			var unported := e.level_name in ["DirtCave4", "DirtCave14"]
			_check(e.disabled == unported, "%s disabled iff target unported" % e.name)
			if not e.disabled:
				var tgt := _room_by_name(rooms, e.level_name)
				_check(tgt != null and tgt.get_node_or_null(e.spawn_pos_name) is Marker2D \
					and tgt.get_node(e.spawn_pos_name).is_in_group("spawn_points"), "%s target %s/%s exists" % [e.name, e.level_name, e.spawn_pos_name])
		elif c is Marker2D:
			var kind := "marker"
			if c.is_in_group("spawn_points"):
				kind = "entry"
				spawns[c.name] = c
			elif c.is_in_group("enemy_spawns"):
				kind = "enemy(%s, unity '%s')" % [c.get_meta("enemy_type"), c.get_meta("unity_name")]
			elif c.is_in_group("rest_chairs"):
				kind = "rest_chair"
			elif c.name == "PlayerStart":
				kind = "player_start"
			print("  %s %s pos=%s solid_cell=%s" % [kind, c.name, c.position, _is_solid(room, c.position)])
			if c.is_in_group("spawn_points") or c.name == "PlayerStart":
				_check(not _is_solid(room, c.position), "%s sits in empty space" % c.name)


func _room_by_name(rooms: Array[Node], nm: String) -> Node:
	for r in rooms:
		if r.name == nm:
			return r
	return null
