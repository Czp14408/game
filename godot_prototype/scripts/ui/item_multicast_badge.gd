class_name ItemMulticastBadge
extends Control
## Small hanging pennant, proportioned to the actual card rather than the slot.
var text := ""
var font_size := 10
var number_font: Font = ItemStatBadge.badge_font

func configure(count: int, quality: int, card_size := Vector2(56, 112)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(clampf(roundf(card_size.x * 0.16), 14, 28), clampf(roundf(card_size.y * 0.12), 12, 16))
	set_meta("quality", quality)
	text = "×%d" % count
	while font_size > 1 and (number_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x-2 or number_font.get_height(font_size) > size.y-2):
		font_size -= 1
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h-2), Vector2(w/2, h), Vector2(0, h-2)]), UiKit.quality_color(int(get_meta("quality", 0))))
	draw_colored_polygon(PackedVector2Array([Vector2(1, 1), Vector2(w-1, 1), Vector2(w-1, h-3), Vector2(w/2, h-1), Vector2(1, h-3)]), GamePalette.PANEL)

	var text_width := number_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (h - number_font.get_height(font_size)) / 2 + number_font.get_ascent(font_size) - 1
	draw_string(number_font, Vector2(roundf((w-text_width)/2), roundf(baseline)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GamePalette.TEXT)
