@tool
class_name RoomExit
extends Area2D
## Port of ChangeLevelTrigger.cs: fires once when the player enters, then asks
## RoomLoader to load the target room. Layer none, mask Player (layer 2).

## Unity: ChangeLevelTrigger.levelName
@export var level_name: String = ""
## Unity: ChangeLevelTrigger.spawnPosName
@export var spawn_pos_name: String = ""
## Exits leading to rooms that are not ported (DirtCave4 / DirtCave14) are disabled.
@export var disabled: bool = false
## Unity: BoxCollider2D.size, in px (converter output).
@export var box_size: Vector2 = Vector2(16, 16):
	set(v):
		box_size = v
		_apply_shape()
## Unity: BoxCollider2D.offset (y negated), in px.
@export var box_offset: Vector2 = Vector2.ZERO:
	set(v):
		box_offset = v
		_apply_shape()

var _activated: bool = false


func _ready() -> void:
	_apply_shape()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _apply_shape() -> void:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if cs == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = box_size
	cs.shape = rect
	cs.position = box_offset


func _on_body_entered(body: Node2D) -> void:
	if _activated or disabled or not body.is_in_group("player"):
		return
	_activated = true
	# Looked up by path so the script also compiles in `-s` tool scripts (autoloads not yet registered).
	var loader: Node = get_node_or_null("/root/RoomLoader")
	if loader:
		loader.call("load_level", level_name, spawn_pos_name)
