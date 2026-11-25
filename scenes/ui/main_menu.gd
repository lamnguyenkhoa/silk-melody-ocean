class_name MainMenu
extends Control
## Port of MainMenu.cs / MainMenu.unity. Buttons: New Game, Continue, Quit.
## Continue is dimmed and inert without a save and gets the initial focus when a save exists
## (otherwise New Game does). New Game does NOT delete an existing save (the delete is commented out in
## Unity) but starts from fresh in-memory defaults; Continue loads the save and goes to its respawn scene.

@onready var new_game_button: SelectButton = $Buttons/NewGame
@onready var continue_button: SelectButton = $Buttons/Continue
@onready var quit_button: SelectButton = $Buttons/Quit
@onready var version_label: Label = $Version

var _starting: bool = false

func _ready() -> void:
	# A menu never inherits a pause / hit-stop from the scene it replaced.
	get_tree().paused = false
	Engine.time_scale = 1.0
	version_label.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var has_save: bool = GameState.save_exists()
	continue_button.inert = not has_save
	new_game_button.chosen.connect(_on_new_game)
	continue_button.chosen.connect(_on_continue)
	quit_button.chosen.connect(_on_quit)
	var first: SelectButton = continue_button if has_save else new_game_button
	first.mute_next_focus = true # Unity plays the sound on the initial selection too; silent here
	first.grab_focus()

func _on_new_game() -> void:
	_start(RoomLoader.StartMode.NEW_GAME)

func _on_continue() -> void:
	_start(RoomLoader.StartMode.CONTINUE)

func _start(mode: RoomLoader.StartMode) -> void:
	if _starting:
		return
	_starting = true
	SceneFlow.to_world(get_tree(), mode, self)

func _on_quit() -> void:
	get_tree().quit()
