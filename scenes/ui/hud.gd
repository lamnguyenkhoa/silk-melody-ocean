class_name Hud
extends CanvasLayer
## Port of HealthUI.cs / SilkBarUI.cs / ShardUI.cs on the UI.prefab layout (plan 7.5).
## Event driven: everything is refreshed from GameState.stats_changed (no polling).
## The layout lives in hud.tscn (Masks, SilkBar, Shards, ToolCircle; Unity reference canvas 1920x1080 ->
## viewport 384x216 = factor 1/5, UI.prefab positions). The variable-count items are instanced from
## hud/hud_mask.tscn and hud/hud_silk_segment.tscn; the script only binds GameState to the nodes.

const MASK_SCENE := preload("res://scenes/ui/hud/hud_mask.tscn")
const SILK_SEGMENT_SCENE := preload("res://scenes/ui/hud/hud_silk_segment.tscn")
const MASK_FULL_PATH := "res://assets/ui/MaskIcon.png"
const MASK_EMPTY_PATH := "res://assets/ui/MaskEmptyIcon.png"
## Atlas regions inside SilkThread.png (filled) / SilkBar.png (empty), see hud/silk_filled.tres, silk_empty.tres.
const SILK_FILLED := preload("res://scenes/ui/hud/silk_filled.tres")
const SILK_EMPTY := preload("res://scenes/ui/hud/silk_empty.tres")

## Unity: HealthUI.InitNumberOfMask lifeblood tint Color(0, 0.75, 1).
const LIFEBLOOD_TINT := Color(0.0, 0.75, 1.0)

var mask_full: Texture2D
var mask_empty: Texture2D
var silk_filled: Texture2D = SILK_FILLED
var silk_empty: Texture2D = SILK_EMPTY

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
## ToolCircleUI (Unity UI.prefab "ToolCircle"): BG = black RadialProgressBar, Fill = the same sprite filled
## radially (origin Bottom, clockwise) by charge / maxCharge, ToolImage = the selected red tool's icon.
## Hidden when no red tool is equipped.
@onready var tool_circle: Control = $ToolCircle
@onready var tool_circle_fill: TextureProgressBar = $ToolCircle/Fill
@onready var tool_circle_icon: TextureRect = $ToolCircle/ToolImage

func _ready() -> void:
	mask_full = load(MASK_FULL_PATH) as Texture2D
	mask_empty = load(MASK_EMPTY_PATH) as Texture2D
	GameState.stats_changed.connect(refresh)
	refresh()

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

## Brings every widget in line with GameState. Rebuilds the mask / silk rows only when their
## number changed (max_hp, lifeblood_hp, max_silk), otherwise just swaps textures.
func refresh() -> void:
	var mask_total: int = GameState.max_hp + GameState.lifeblood_hp
	if masks.size() != mask_total:
		_rebuild(masks_box, masks, mask_total, MASK_SCENE)
	for i in masks.size():
		if i < GameState.max_hp:
			masks[i].texture = mask_full if i < GameState.current_hp else mask_empty
			masks[i].modulate = Color.WHITE
		else:
			# Unity: lifeblood masks keep the prefab sprite (full mask), tinted blue.
			masks[i].texture = mask_full
			masks[i].modulate = LIFEBLOOD_TINT

	if silk_segments.size() != GameState.max_silk:
		_rebuild(silk_box, silk_segments, GameState.max_silk, SILK_SEGMENT_SCENE)
	for i in silk_segments.size():
		silk_segments[i].texture = silk_filled if i < GameState.current_silk else silk_empty

	shard_count.text = str(GameState.copper_shard)
	_refresh_tool_circle()

func _rebuild(box: Container, list: Array[TextureRect], count: int, scene: PackedScene) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	list.clear()
	for i in count:
		var rect := scene.instantiate() as TextureRect
		box.add_child(rect)
		list.append(rect)
