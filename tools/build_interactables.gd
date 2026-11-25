extends SceneTree
## Builds scenes/interactables/rest_chair.tscn (P6). Run before build_rooms:
##   godot --headless --path . -s tools/build_interactables.gd
## Values from Assets/Interactable/RestChair/RestChair.prefab (Unity units * 16 px, y negated):
##   BoxCollider2D size (2.6963, 1.4265), offset (0.0054, -0.8663); SitSpot local (0, -0.2);
##   InteractText anchored (0.02, 1.41); sprite PPU 64 (256 px sheet -> scale 0.25), sorting order -1.

const OUT_PATH := "res://scenes/interactables/rest_chair.tscn"
const SPRITE_PATH := "res://assets/props/RestChair.png"
const SFX_PATH := "res://assets/sfx/save_sfx.ogg"
const SPRITE_SCALE := 0.25
const TRIGGER_SIZE := Vector2(43.14, 22.82)
const TRIGGER_OFFSET := Vector2(0.087, 13.86)
const SIT_SPOT := Vector2(0.0, 3.2)
const LABEL_CENTER := Vector2(0.32, -22.56)
const LABEL_SIZE := Vector2(48, 12)
## Unity TMP text of InteractText / SavingText.
const INTERACT_TEXT := "Rest"
const SAVING_TEXT := "Saving..."
const FONT_SIZE := 8
const UI_LAYER := 6

func _initialize() -> void:
	await process_frame # autoloads must exist before rest_chair.gd compiles
	var script: GDScript = load("res://scenes/interactables/rest_chair.gd")
	if script == null:
		push_error("build_interactables: rest_chair.gd failed to load")
		quit(1)
		return

	var root := Area2D.new()
	root.name = "RestChair"
	root.set_script(script)
	root.collision_layer = 0
	root.collision_mask = 128

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load(SPRITE_PATH)
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.z_index = -1
	_add(root, root, sprite)

	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = TRIGGER_SIZE
	cs.shape = rect
	cs.position = TRIGGER_OFFSET
	_add(root, root, cs)

	var sit := Marker2D.new()
	sit.name = "SitSpot"
	sit.position = SIT_SPOT
	_add(root, root, sit)

	var label := Label.new()
	label.name = "InteractLabel"
	label.text = INTERACT_TEXT
	label.size = LABEL_SIZE
	label.position = LABEL_CENTER - LABEL_SIZE * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.z_index = 20
	_add(root, root, label)

	var ui := CanvasLayer.new()
	ui.name = "Ui"
	ui.layer = UI_LAYER
	_add(root, root, ui)

	var flash := ColorRect.new()
	flash.name = "SoftFlash"
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(root, ui, flash)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)

	var saving := Label.new()
	saving.name = "SavingText"
	saving.text = SAVING_TEXT
	saving.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	saving.mouse_filter = Control.MOUSE_FILTER_IGNORE
	saving.add_theme_font_size_override("font_size", FONT_SIZE)
	saving.add_theme_constant_override("outline_size", 2)
	saving.add_theme_color_override("font_outline_color", Color.BLACK)
	_add(root, ui, saving)
	# Unity: anchored bottom right, offset (-34, 29) on the 1920x1080 canvas -> /5.
	saving.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	saving.offset_left = -76.0
	saving.offset_right = -7.0
	saving.offset_top = -20.0
	saving.offset_bottom = -6.0

	var sfx := AudioStreamPlayer.new()
	sfx.name = "SaveSfx"
	sfx.stream = load(SFX_PATH)
	_add(root, root, sfx)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_PATH)
	print("build_interactables: saved %s (err %d)" % [OUT_PATH, err])
	root.free()
	quit(0 if err == OK else 1)


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
