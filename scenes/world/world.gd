extends Node2D
## Persistent world root (plan section 7.1). P0: placeholder only; no player yet.
## TODO(P2/P6): Player, GameCamera, HUD, Fader, Vignette; call RoomLoader.start().

@onready var room_container: Node2D = $RoomContainer
