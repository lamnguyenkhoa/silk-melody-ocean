class_name RestChair
extends Area2D
## Port of RestChair.cs + InRangeInteractable.cs (plan 7.3). Area2D (mask PlayerTrigger) sized like
## the prefab's trigger BoxCollider2D. Children (built by tools/build_interactables.gd): Sprite2D,
## CollisionShape2D, SitSpot (Marker2D), InteractLabel, Ui (CanvasLayer: SoftFlash, SavingText), SaveSfx.

## Unity: RestChair.SoftFlash start alpha (100 / 255) and decay per second.
const SOFT_FLASH_ALPHA: float = 100.0 / 255.0
const SOFT_FLASH_DECAY: float = 0.3
## Unity: SavingText coroutine duration, seconds.
const SAVING_TEXT_TIME: float = 1.0
## Unity checks Movement.y == 1 / == -1 (a fully held direction; diagonals are normalised below 1).
const FULL_PRESS: float = 0.999

var player_in_range: bool = false
var sitting: bool = false
var _player: Player
var _flash_gen: int = 0
var _text_gen: int = 0

@onready var sit_spot: Marker2D = $SitSpot
@onready var interact_label: Label = $InteractLabel
@onready var soft_flash: ColorRect = $Ui/SoftFlash
@onready var saving_text: Label = $Ui/SavingText
@onready var save_sfx: AudioStreamPlayer = $SaveSfx

func _ready() -> void:
	add_to_group("rest_chairs")
	collision_layer = 0
	collision_mask = 128 # PlayerTrigger
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	interact_label.visible = false
	saving_text.visible = false
	soft_flash.color.a = 0.0

func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player

func _physics_process(_delta: float) -> void:
	var p := _get_player()
	if p == null:
		return
	var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Godot up is negative y; Unity's Movement.y is positive up.
	var press_up: bool = -move.y >= FULL_PRESS
	var press_down: bool = move.y >= FULL_PRESS
	if player_in_range and press_up and not sitting and not p.in_menu:
		get_on_chair()
		_start_soft_flash()
		_start_saving_text()
	if sitting and press_down and not p.in_menu:
		_get_off_chair()

func _process(delta: float) -> void:
	if soft_flash.color.a > 0.0:
		soft_flash.color.a = maxf(soft_flash.color.a - SOFT_FLASH_DECAY * delta, 0.0)

func _get_off_chair() -> void:
	var p := _get_player()
	sitting = false
	p.resting = false
	p.is_kinematic = false
	p.end_rest_invulnerability()
	interact_label.visible = true

## GetOnChair(): also called by RoomLoader when respawning at this chair (no flash / saving text).
func get_on_chair() -> void:
	var p := _get_player()
	if p == null:
		return
	sitting = true
	p.resting = true
	p.rest_chair_recovery()
	p.velocity = Vector2.ZERO
	p.is_kinematic = true
	p.global_position = sit_spot.global_position
	RoomLoader.update_spawn_point(name)
	p.begin_rest_invulnerability()
	GameState.refill_red_tools() # RestChair.GetOnChair: RefillRedTool before the save
	save_sfx.play()
	GameState.save()
	interact_label.visible = false

func _start_soft_flash() -> void:
	_flash_gen += 1
	soft_flash.color.a = SOFT_FLASH_ALPHA

func _start_saving_text() -> void:
	_text_gen += 1
	var my_gen: int = _text_gen
	saving_text.visible = true
	await get_tree().create_timer(SAVING_TEXT_TIME, false, true).timeout
	if my_gen == _text_gen:
		saving_text.visible = false

func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player:
		player_in_range = true
		if not sitting:
			interact_label.visible = true

func _on_area_exited(area: Area2D) -> void:
	if area.get_parent() is Player:
		player_in_range = false
		interact_label.visible = false
