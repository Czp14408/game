class_name ItemStatBadge
extends Control
## Beveled pixel crest straddling the upper card frame.

var kind := ""
var value_text := ""
var caption: Label
var natural_width := 24.0
static var badge_font: Font = _make_number_font()

static func _make_number_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font

func configure(stat: Dictionary, width := 72.0) -> void:
	kind = stat["kind"]
	value_text = stat["text"]
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colors: Dictionary = GamePalette.ATTRIBUTES[kind]
	caption = UiKit.label(value_text, ItemCardLayout.BADGE_FONT_SIZE, colors["ink"])
	caption.add_theme_font_override("font", badge_font)
	caption.add_theme_color_override("font_shadow_color", GamePalette.BACKGROUND)
	caption.add_theme_constant_override("shadow_offset_x", 1 if colors["ink"] == GamePalette.TEXT else 0)
	caption.add_theme_constant_override("shadow_offset_y", 1 if colors["ink"] == GamePalette.TEXT else 0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	natural_width = width
	size = Vector2(width, ItemCardLayout.BADGE_HEIGHT)
	caption.position = Vector2(2, 0)
	caption.size = Vector2(maxf(size.x - 4, 1), size.y)
	var font_size := ItemCardLayout.BADGE_FONT_SIZE
	while font_size > 1 and badge_font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > caption.size.x:
		font_size -= 1
	caption.add_theme_font_size_override("font_size", font_size)
	if font_size < 10:
		caption.add_theme_constant_override("shadow_offset_x", 0)
		caption.add_theme_constant_override("shadow_offset_y", 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(caption)
	queue_redraw()

func _draw() -> void:
	var fill: Color = GamePalette.ATTRIBUTES[kind]["fill"]
	var shades := {
		"attack": ["#6B2634", "#E86B67"], "shield": ["#8A6625", "#FFF1A1"],
		"poison": ["#0D3426", "#2F8654"], "burn": ["#8C421E", "#F4AC55"],
		"heal": ["#185C3A", "#A5E6A0"]}
	var dark := Color(shades[kind][0])
	var light := Color(shades[kind][1])
	var w := size.x
	var h := size.y
	var outline := PackedVector2Array([Vector2(4, 0), Vector2(w-4, 0), Vector2(w, 5),
		Vector2(w, h-5), Vector2(w-4, h), Vector2(4, h), Vector2(0, h-5), Vector2(0, 5)])
	draw_colored_polygon(outline, GamePalette.BACKGROUND)
	draw_colored_polygon(PackedVector2Array([Vector2(5, 2), Vector2(w-5, 2), Vector2(w-2, 6),
		Vector2(w-2, h-6), Vector2(w-5, h-2), Vector2(5, h-2), Vector2(2, h-6), Vector2(2, 6)]), dark)
	draw_rect(Rect2(4, 5, w-8, h-10), fill)
	draw_rect(Rect2(5, 2, w-10, 2), light)
	draw_rect(Rect2(2, 6, 2, h-12), light)
	draw_rect(Rect2(w-4, 6, 2, h-12), dark)
