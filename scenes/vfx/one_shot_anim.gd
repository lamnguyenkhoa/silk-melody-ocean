class_name OneShotAnim
extends Node2D
## Plays its AnimationPlayer's "play" clip once on spawn, then frees itself
## (Unity: SlashSpark / HurtSpark prefabs destroyed at the end of their clip).

func _ready() -> void:
	var ap := $AnimationPlayer as AnimationPlayer
	ap.animation_finished.connect(func(_clip: StringName) -> void: queue_free())
	ap.play(&"play")
