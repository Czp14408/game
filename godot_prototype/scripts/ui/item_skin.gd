class_name ItemSkin
extends RefCounted
## Pixel frames are shared by item cards and tooltips; corners never stretch.

const ROOT := "res://assets/ui/item_frames_v1/"
static var _theme: Dictionary = {}

static func settings() -> Dictionary:
	if _theme.is_empty():
		_theme = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "theme.json"))
	return _theme

static func frame_style(quality: int, selected: bool = false, tooltip: bool = false) -> StyleBoxTexture:
	var config := settings()
	var entry: Dictionary = config["qualities"][clampi(quality, 0, 3)]
	var style := StyleBoxTexture.new()
	style.texture = load(ROOT + String(entry["selected" if selected else "frame"]))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, float(config["slice"]))
		style.set_content_margin(side, float(config["tooltip_padding"] if tooltip else config["image_inset"]))
	return style
