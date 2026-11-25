class_name GameMenuUi
extends RefCounted
## Small UI construction helpers shared by the game menu pages (labels, bars, fonts, textures).

const BOLD := 1
const ITALIC := 2
const UNDERLINE := 4

## TMP font styles: Bold (embolden) and Italic (skew) on top of the default font. A new FontVariation per
## call: a static cache would still be alive at exit and Godot reports it as a leaked resource.
static func font_for(style: int) -> Font:
	if style & ITALIC:
		var italic := FontVariation.new()
		italic.base_font = ThemeDB.fallback_font
		italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
		return italic
	if style & BOLD:
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 0.7
		return bold
	return ThemeDB.fallback_font

## Text label filling `rect` (screen px). `h_align` / `v_align` are the Godot alignment enums.
static func make_label(text: String, rect: Rect2, font_px: int, h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		v_align: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER, style: int = 0, wrap: bool = true) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.horizontal_alignment = h_align
	label.vertical_alignment = v_align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_font_override("font", font_for(style))
	label.add_theme_color_override("font_color", Color.WHITE)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func make_rect(rect: Rect2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func make_texture(texture: Texture2D, rect: Rect2) -> TextureRect:
	var t := TextureRect.new()
	# expand_mode first: otherwise the texture's own size becomes the minimum size and `size` is clamped.
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture = texture
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## Texture of `path`, or the sub-rect `region` (Godot top-left px) of it.
static func load_texture(path: String, region: Rect2 = Rect2()) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null or region.size == Vector2.ZERO:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	return atlas

## Control with no size, used as a scalable / movable origin for children laid out around a centre point.
static func make_origin(pos: Vector2) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = Vector2.ZERO
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
