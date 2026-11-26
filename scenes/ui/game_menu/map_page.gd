class_name MapPage
extends MenuPage
## Port of MapPage.cs / RoomDisplay.cs / PathDisplay.cs / PlayerMarker (+ the MapGroup layout of
## InventoryMenu.prefab). pages/map_page.tscn holds MapContent > area(s) > PathGroup (one ColorRect per path,
## metadata "rooms" = the two room names it connects) and one ColorRect per room (with its icon as child).
## Only rooms in GameState.world.visited_rooms are shown (a path is shown when either of its rooms was
## visited). On show the content is reset to scale 1 and centred on the current room, with the pulsing mask
## marker on it. Pan: W/A/S/D / right stick, zoom: R / F (or the triggers), scale clamped to 0.2..3.

const MARKER_SCENE := preload("res://scenes/ui/game_menu/pages/map_player_marker.tscn")

## Room name -> room rect node.
var room_nodes: Dictionary = {}
## Room name -> its area node.
var room_areas: Dictionary = {}
var path_nodes: Array[Control] = []
var marker: TextureRect

var _path_rooms: Dictionary = {} # path node -> [room0, room1]

@onready var content: Control = $MapContent

func _ready() -> void:
	for area: Control in content.get_children():
		for child in area.get_children():
			var node := child as Control
			if node.name == &"PathGroup":
				for path: Control in node.get_children():
					path_nodes.append(path)
					_path_rooms[path] = Array(path.get_meta("rooms") as PackedStringArray)
			else:
				room_nodes[node.name] = node
				room_areas[node.name] = area

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
	marker = MARKER_SCENE.instantiate() as TextureRect
	room.add_child(marker)
	marker.position = (room.size - marker.size) * 0.5
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
