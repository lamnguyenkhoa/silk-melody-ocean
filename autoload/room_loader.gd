extends Node
## Port of LevelLoader.cs + ChangeLevelTrigger.cs. STUB in P0.
## TODO(P6): implement room swapping under World/RoomContainer, fading, player
## placement at spawn markers, camera limits, respawn (plan §7.2).

## Unity: LevelLoader.transitionTime, seconds.
var transition_time: float = 1.0

## TODO(P6): fade out, free old room, instance res://scenes/rooms/<snake_case(room_name)>.tscn,
## place the player at the Marker2D named spawn_name, fade in.
func load_level(_room_name: String, _spawn_name: String) -> void:
	pass

## TODO(P6): set do_respawn and load GameState.respawn_scene (chair or respawn_pos).
func respawn() -> void:
	pass

## TODO(P6): first boot - load GameState.respawn_scene and place the player.
func start() -> void:
	pass
