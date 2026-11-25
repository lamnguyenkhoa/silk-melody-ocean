class_name Hud
extends CanvasLayer
## Port of HealthUI.cs / SilkBarUI.cs / ShardUI.cs on the UI.prefab layout (plan 7.5).
## Event driven: everything is refreshed from GameState.stats_changed (no polling).
## Layout: Unity reference canvas 1920x1080 -> viewport 384x216 = factor 1/5 (UI.prefab positions).

const MASK_FULL_PATH := "res://assets/ui/MaskIcon.png"
const MASK_EMPTY_PATH := "res://assets/ui/MaskEmptyIcon.png"
const SILK_BAR_PATH := "res://assets/ui/SilkBar.png"
const SILK_THREAD_PATH := "res://assets/ui/SilkThread.png"
const SHARD_ICON_PATH := "res://assets/props/CopperShard.png"

## Unity: HealthUI.InitNumberOfMask lifeblood tint Color(0, 0.75, 1).
const LIFEBLOOD_TINT := Color(0.0, 0.75, 1.0)

## Unity: UI.prefab "Health" anchored (219, -27) from the top-left, HealthMaskUI 100x100 with
## spacing 24, all /5 for the 384x216 viewport.
const MASKS_POS := Vector2(43.8, 5.4)
const MASK_SIZE := Vector2(20.0, 20.0)
const MASK_SEPARATION: int = 5
## Unity: "SilkBar" anchored (123, -160), scale (1.5, 1.2); sprites use native size = px * 100/64
## canvas units. Pixel width factor 1.5 * 100/64 / 5 = 0.469, height factor 1.2 * 100/64 / 5 = 0.375.
const SILK_BAR_POS := Vector2(24.6, 32.0)
const SILK_SEGMENT_SIZE := Vector2(3.0, 12.0) # SilkThread_0 / SilkBar_1: 6x32 px
const SILK_CAP_SIZE := Vector2(7.0, 12.0) # SilkBar_0 / SilkBar_2: 14x32 px
## Atlas regions inside SilkBar.png / SilkThread.png (Unity sprite rects; y is 0 for all, full height).
const SILK_LEFT_CAP_REGION := Rect2(0, 0, 14, 32)
const SILK_EMPTY_REGION := Rect2(45, 0, 6, 32)
const SILK_RIGHT_CAP_REGION := Rect2(82, 0, 14, 32)
const SILK_FILLED_REGION := Rect2(13, 0, 6, 32)
## Unity: "CopperShard" anchored (34, -254), scale 0.75; icon 100x100, text offset 124, font 54 (/5).
const SHARDS_POS := Vector2(6.8, 50.8)
const SHARD_ICON_SIZE := Vector2(15.0, 15.0)
const SHARD_TEXT_POS := Vector2(18.6, 2.0)
const SHARD_FONT_SIZE: int = 8
const SHARD_OUTLINE_SIZE: int = 2

## Unity: UI.prefab "ToolCircle" (ToolCircleUI.cs) anchored at the screen centre (-691, 249), 100x100 (/5).
## BG = black RadialProgressBar, Fill = the same sprite filled radially (origin Bottom, clockwise) by
## charge / maxCharge, ToolImage = the selected red tool's icon. Hidden when no red tool is equipped.
const TOOL_CIRCLE_PATH := "res://assets/ui/tools/RadialProgressBar.png"
const TOOL_CIRCLE_CENTER := Vector2(53.8, 58.2)
const TOOL_CIRCLE_SIZE := Vector2(20.0, 20.0)
const TOOL_CIRCLE_START_ANGLE: float = 180.0

var mask_full: Texture2D
var mask_empty: Texture2D
var silk_filled: AtlasTexture
var silk_empty: AtlasTexture

## Tool circle widgets (null until _ready).
var tool_circle: Control
var tool_circle_fill: TextureProgressBar
var tool_circle_icon: TextureRect

## Mask icons in order: max_hp permanent ones, then lifeblood ones (test / debug access).
var masks: Array[TextureRect] = []
var silk_segments: Array[TextureRect] = []

@onready var masks_box: HBoxContainer = $Masks
@onready var silk_bar: HBoxContainer = $SilkBar
@onready var silk_left_cap: TextureRect = $SilkBar/LeftCap
@onready var silk_right_cap: TextureRect = $SilkBar/RightCap
@onready var silk_box: HBoxContainer = $SilkBar/Segments
@onready var shards: Control = $Shards
@onready var shard_icon: TextureRect = $Shards/Icon
@onready var shard_count: Label = $Shards/Count

func _ready() -> void:
	mask_full = load(MASK_FULL_PATH) as Texture2D
	mask_empty = load(MASK_EMPTY_PATH) as Texture2D
	var thread_sheet := load(SILK_THREAD_PATH) as Texture2D
	var bar_sheet := load(SILK_BAR_PATH) as Texture2D
	silk_filled = _atlas(thread_sheet, SILK_FILLED_REGION)
	silk_empty = _atlas(bar_sheet, SILK_EMPTY_REGION)

	masks_box.position = MASKS_POS
	masks_box.add_theme_constant_override("separation", MASK_SEPARATION)
	silk_bar.position = SILK_BAR_POS
	silk_bar.add_theme_constant_override("separation", 0)
	silk_box.add_theme_constant_override("separation", 0)
	_setup_icon(silk_left_cap, _atlas(bar_sheet, SILK_LEFT_CAP_REGION), SILK_CAP_SIZE)
	_setup_icon(silk_right_cap, _atlas(bar_sheet, SILK_RIGHT_CAP_REGION), SILK_CAP_SIZE)
	shards.position = SHARDS_POS
	_setup_icon(shard_icon, load(SHARD_ICON_PATH) as Texture2D, SHARD_ICON_SIZE)
	shard_count.position = SHARD_TEXT_POS
	shard_count.add_theme_font_size_override("font_size", SHARD_FONT_SIZE)
	shard_count.add_theme_color_override("font_outline_color", Color.BLACK)
	shard_count.add_theme_constant_override("outline_size", SHARD_OUTLINE_SIZE)

	_build_tool_circle()
	GameState.stats_changed.connect(refresh)
	refresh()

func _build_tool_circle() -> void:
	tool_circle = Control.new()
	tool_circle.name = "ToolCircle"
	tool_circle.position = TOOL_CIRCLE_CENTER - TOOL_CIRCLE_SIZE * 0.5
	tool_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tool_circle)
	var circle_texture := load(TOOL_CIRCLE_PATH) as Texture2D
	var bg := TextureRect.new()
	bg.name = "BG"
	_setup_icon(bg, circle_texture, TOOL_CIRCLE_SIZE)
	bg.size = TOOL_CIRCLE_SIZE
	bg.modulate = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_circle.add_child(bg)
	# TextureProgressBar draws its texture at native size: scale it down to the circle size.
	tool_circle_fill = TextureProgressBar.new()
	tool_circle_fill.name = "Fill"
	tool_circle_fill.texture_progress = circle_texture
	tool_circle_fill.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	tool_circle_fill.radial_initial_angle = TOOL_CIRCLE_START_ANGLE
	tool_circle_fill.radial_fill_degrees = 360.0
	tool_circle_fill.min_value = 0.0
	tool_circle_fill.max_value = 1.0
	tool_circle_fill.step = 0.0
	tool_circle_fill.value = 0.0
	tool_circle_fill.scale = TOOL_CIRCLE_SIZE / circle_texture.get_size()
	tool_circle_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_circle.add_child(tool_circle_fill)
	tool_circle_icon = TextureRect.new()
	tool_circle_icon.name = "ToolImage"
	_setup_icon(tool_circle_icon, null, TOOL_CIRCLE_SIZE)
	tool_circle_icon.size = TOOL_CIRCLE_SIZE
	tool_circle_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_circle.add_child(tool_circle_icon)
	tool_circle.visible = false

## ToolCircleUI.Update: hidden without equipped red tools, otherwise the selected tool's charge fraction
## and icon.
func _refresh_tool_circle() -> void:
	var tool_id: int = GameState.get_selected_red_tool()
	if tool_id < 0:
		tool_circle.visible = false
		return
	tool_circle.visible = true
	tool_circle_fill.value = GameState.get_red_tool_charge(tool_id) / ToolData.red_max_charge(tool_id)
	var icon: Texture2D = load(ToolData.tool_def(ToolData.ToolKind.RED, tool_id)["icon"] as String) as Texture2D
	if tool_circle_icon.texture != icon:
		tool_circle_icon.texture = icon

func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = sheet
	a.region = region
	return a

func _setup_icon(rect: TextureRect, texture: Texture2D, size: Vector2) -> void:
	rect.texture = texture
	rect.custom_minimum_size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE

## Brings every widget in line with GameState. Rebuilds the mask / silk rows only when their
## number changed (max_hp, lifeblood_hp, max_silk), otherwise just swaps textures.
func refresh() -> void:
	var mask_total: int = GameState.max_hp + GameState.lifeblood_hp
	if masks.size() != mask_total:
		_rebuild(masks_box, masks, mask_total, MASK_SIZE)
	for i in masks.size():
		if i < GameState.max_hp:
			masks[i].texture = mask_full if i < GameState.current_hp else mask_empty
			masks[i].modulate = Color.WHITE
		else:
			# Unity: lifeblood masks keep the prefab sprite (full mask), tinted blue.
			masks[i].texture = mask_full
			masks[i].modulate = LIFEBLOOD_TINT

	if silk_segments.size() != GameState.max_silk:
		_rebuild(silk_box, silk_segments, GameState.max_silk, SILK_SEGMENT_SIZE)
	for i in silk_segments.size():
		silk_segments[i].texture = silk_filled if i < GameState.current_silk else silk_empty

	shard_count.text = str(GameState.copper_shard)
	_refresh_tool_circle()

func _rebuild(box: Container, list: Array[TextureRect], count: int, size: Vector2) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	list.clear()
	for i in count:
		var rect := TextureRect.new()
		_setup_icon(rect, null, size)
		box.add_child(rect)
		list.append(rect)
