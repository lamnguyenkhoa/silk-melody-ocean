class_name MenuPage
extends Control
## Base of the game menu tab pages. The page is built once; `page_shown` / `page_hidden` are Unity's
## OnEnable / OnDisable (the menu is persistent, pages are shown and hidden by SetActive).

## Plays the menu's "moving" sound (set by the GameMenu).
var menu: Node

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func page_shown() -> void:
	pass

func page_hidden() -> void:
	pass

## Control that gets the keyboard / gamepad focus when the tab opens (null = nothing is focused).
func initial_focus() -> Control:
	return null

func play_moving() -> void:
	if menu != null and menu.has_method("play_moving"):
		menu.call("play_moving")
