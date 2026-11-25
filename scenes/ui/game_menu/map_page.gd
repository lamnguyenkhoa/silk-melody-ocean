class_name MapPage
extends MenuPage
## Port of MapPage.cs / RoomDisplay.cs / PathDisplay.cs / PlayerMarker (+ the MapGroup layout of
## InventoryMenu.prefab). MapContent holds the area(s); only rooms in GameState.world.visited_rooms are shown
## (a path is shown when either of its rooms was visited). On show the content is reset to scale 1 and centred on
## the current room, with the pulsing mask marker on it. Pan: W/A/S/D / right stick, zoom: R / F (or the triggers),
## scale clamped to 0.2..3.

var content: Control
## Room name -> room rect node.
var room_nodes: Dictionary = {}
## Room name -> its area node.
var room_areas: Dictionary = {}
var path_nodes: Array[Control] = []
var marker: TextureRect

var _path_rooms: Dictionary = {} # path node -> [room0, room1]

func _ready() -> void:
	content = GameMenuUi.make_origin(GameMenuData.SCREEN_CENTER)
	content.name = "MapContent"
	add_child(content)
	for area_def: Dictionary in GameMenuData.MAP_AREAS:
		var area := GameMenuUi.make_origin(GameMenuData.to_px(area_def["pos"]))
		area.name = area_def["name"]
		content.add_child(area)
		var path_group := GameMenuUi.make_origin(Vector2.ZERO)
		path_group.name = "PathGroup"
		area.add_child(path_group)
		for path_def: Dictionary in area_def["paths"]:
			var path := _make_centred_rect(path_def["pos"], GameMenuData.MAP_PATH_SIZE, GameMenuData.MAP_PATH_COLOR)
			path.name = "%s %s" % [String(path_def["room0"]).trim_prefix("DirtCave"), String(path_def["room1"]).trim_prefix("DirtCave")]
			# Unity z rotation is counter-clockwise, Godot's is clockwise.
			path.rotation = -deg_to_rad(float(path_def["rot"]))
			path_group.add_child(path)
			path_nodes.append(path)
			_path_rooms[path] = [path_def["room0"], path_def["room1"]]
		for room_def: Dictionary in area_def["rooms"]:
			var room := _make_centred_rect(room_def["pos"], room_def["size"], GameMenuData.MAP_ROOM_COLOR)
			room.name = room_def["name"]
			area.add_child(room)
			room_nodes[room.name] = room
			room_areas[room.name] = area
			if room_def.has("icon"):
				var icon_size: Vector2 = room_def.get("icon_size", GameMenuData.MAP_ICON_SIZE) * GameMenuData.CANVAS_TO_PX
				var icon_pos: Vector2 = GameMenuData.to_px(room_def.get("icon_pos", Vector2.ZERO))
				var icon := GameMenuUi.make_texture(load(room_def["icon"]) as Texture2D, Rect2(room.size * 0.5 + icon_pos - icon_size * 0.5, icon_size))
				icon.name = "Image"
				room.add_child(icon)

## A Unity element with centre `pos` (relative to the parent origin) and `size` (canvas units): Control with
## its pivot at the centre so rotation turns it in place.
func _make_centred_rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := GameMenuUi.make_rect(Rect2(GameMenuData.to_px(pos) - size * (GameMenuData.CANVAS_TO_PX * 0.5), size * GameMenuData.CANVAS_TO_PX), color)
	r.pivot_offset = r.size * 0.5
	return r

## RoomDisplay / PathDisplay.OnEnable + MapPage.OnEnable (UpdatePlayerPosOnMap).
func page_shown() -> void:
	var visited: Array[String] = GameState.world.visited_rooms
	for room_name: String in room_nodes:
		(room_nodes[room_name] as Control).visible = visited.has(room_name)
	for path: Control in path_nodes:
		var rooms: Array = _path_rooms[path]
		path.visible = visited.has(rooms[0]) or visited.has(rooms[1])
	update_player_pos(RoomLoader.current_room_name)

## PlayerMarker is destroyed on disable.
func page_hidden() -> void:
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	marker = null

## MapPage.UpdatePlayerPosOnMap: marker as a child of the current room, content reset to scale 1 and centred.
func update_player_pos(current_scene_name: String) -> bool:
	page_hidden()
	if not room_nodes.has(current_scene_name):
		return false
	var room := room_nodes[current_scene_name] as Control
	var area := room_areas[current_scene_name] as Control
	marker = GameMenuUi.make_texture(load(GameMenuData.MAP_MARKER_TEXTURE) as Texture2D,
			Rect2(room.size * 0.5 - GameMenuData.MAP_MARKER_SIZE * GameMenuData.CANVAS_TO_PX * 0.5, GameMenuData.MAP_MARKER_SIZE * GameMenuData.CANVAS_TO_PX))
	marker.name = "PlayerMarker"
	marker.pivot_offset = marker.size * 0.5
	room.add_child(marker)
	# Auto centring: content = -(area position) - (room position), in the content's own (unscaled) space.
	content.scale = Vector2.ONE
	content.position = GameMenuData.SCREEN_CENTER - area.position - (room.position + room.size * 0.5)
	return true

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	step(Input.get_vector(&"map_pan_left", &"map_pan_right", &"map_pan_up", &"map_pan_down"),
			Input.get_axis(&"map_zoom_out", &"map_zoom_in"), delta)
	if marker != null and is_instance_valid(marker):
		var s: float = 1.0 + sin(Time.get_ticks_msec() * 0.001 * GameMenuData.MAP_MARKER_PULSE_SPEED) * GameMenuData.MAP_MARKER_PULSE_AMPLITUDE
		marker.scale = Vector2(s, s)

## MapPage.HandleMapControl: pan (content moves against the input), zoom, scale clamp 0.2..3.
func step(pan: Vector2, zoom: float, delta: float) -> void:
	content.position -= pan * GameMenuData.MAP_MOVE_SPEED * GameMenuData.CANVAS_TO_PX * delta
	var s: float = content.scale.x + delta * zoom * GameMenuData.MAP_ZOOM_SPEED
	s = clampf(s, GameMenuData.MAP_ZOOM_MIN, GameMenuData.MAP_ZOOM_MAX)
	content.scale = Vector2(s, s)
