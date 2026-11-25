class_name PauseMenu
extends CanvasLayer
## Port of PauseMenu.cs + PauseMenu.prefab ("PAUSED" over a black 0.78 panel), extended with the buttons
## Resume / Main Menu / Quit (Unity only shows the title).
## Pausing uses SceneTree.paused (this layer and its buttons are PROCESS_MODE_ALWAYS), never
## Engine.time_scale, which Hitstop owns. Like Unity it adds +1 to the player's control lock while open
## and removes it again on close. Pausing is refused while the player is dead or a room transition is
## running (see can_pause); during hit-stop it is allowed (hit-stop only changes time_scale).

signal paused_changed(is_paused: bool)

## The player whose control lock is held while the menu is open (set by World).
var player: Player

@onready var resume_button: SelectButton = $Holder/Buttons/Resume
@onready var main_menu_button: SelectButton = $Holder/Buttons/MainMenu
@onready var quit_button: SelectButton = $Holder/Buttons/Quit
@onready var holder: Control = $Holder

var _open: bool = false
var _locked_player: Player
var _leaving: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.chosen.connect(close)
	main_menu_button.chosen.connect(_on_main_menu)
	quit_button.chosen.connect(_on_quit)

func _exit_tree() -> void:
	# The world was freed while open (e.g. quit to menu): never leave the tree paused.
	if _open:
		_open = false
		var tree := get_tree()
		if tree != null:
			tree.paused = false

func is_open() -> bool:
	return _open

## Pausing is blocked while dead (the respawn transition is running) and during room transitions /
## boot (fade out, swap): pausing there would freeze the transition timers' consumers mid-swap.
func can_pause() -> bool:
	if _leaving or player == null or not is_instance_valid(player):
		return false
	return not player.is_dead and not RoomLoader.is_transitioning()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

## PauseMenu.Update pause branch. Returns false if pausing is currently blocked.
func open() -> bool:
	if _open:
		return true
	if not can_pause():
		return false
	_open = true
	_locked_player = player
	_locked_player.control_lock += 1
	visible = true
	get_tree().paused = true
	resume_button.mute_next_focus = true
	resume_button.grab_focus()
	paused_changed.emit(true)
	return true

## PauseMenu.Update unpause branch (also the Resume button).
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _locked_player != null and is_instance_valid(_locked_player):
		_locked_player.control_lock = maxi(_locked_player.control_lock - 1, 0)
	_locked_player = null
	get_tree().paused = false
	paused_changed.emit(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or (_open and event.is_action_pressed(&"ui_cancel")):
		toggle()
		get_viewport().set_input_as_handled()

func _on_main_menu() -> void:
	if _leaving:
		return
	close()
	_leaving = true
	# No save prompt: saving only happens at the rest chair (as in Unity).
	SceneFlow.to_main_menu(get_tree(), get_parent())

func _on_quit() -> void:
	get_tree().quit()
