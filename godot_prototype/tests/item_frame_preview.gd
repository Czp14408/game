extends SceneTree
## Preview the shared pixel frames at all three aspect ratios without placeholder item art.

func _initialize() -> void:
	call_deferred("show_templates")

func show_templates() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	DisplayServer.window_set_size(root.size)
	var canvas := Control.new()
	canvas.theme = UiKit.make_theme()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	canvas.add_child(UiKit.overlay(Color("10151f"), Vector2(root.size)))
	canvas.add_child(UiKit.abs_label("通用像素品质框 · 第一版", 26, UiKit.COL_TEXT, Rect2i(40, 20, 1000, 40)))
	canvas.add_child(UiKit.abs_label("小 1:2    中 2:2    大 3:2   ｜   同品质共用框体，图案由每件物品单独提供", 16,
		UiKit.COL_MUTED, Rect2i(40, 64, 1300, 28)))
	var catalog := ContentCatalog.load_default()
	for quality in range(4):
		var y := 120 + quality * 185
		canvas.add_child(UiKit.abs_label(PriceTable.quality_name(quality), 20, UiKit.COL_TEXT, Rect2i(40, y, 120, 30)))
		var x := 180
		for span in [1, 2, 3]:
			var panel := Panel.new()
			panel.position = Vector2(x, y)
			panel.size = Vector2(64 * span, 128)
			panel.add_theme_stylebox_override("panel", ItemSkin.frame_style(quality))
			canvas.add_child(panel)
			panel.add_child(UiKit.abs_label(["小", "中", "大"][span - 1], 16, UiKit.COL_MUTED,
				Rect2i(8, 42, int(panel.size.x) - 16, 35), HORIZONTAL_ALIGNMENT_CENTER))
			x += 64 * span + 36
		var selected := Panel.new()
		selected.position = Vector2(680, y)
		selected.size = Vector2(128, 128)
		selected.add_theme_stylebox_override("panel", ItemSkin.frame_style(quality, true))
		canvas.add_child(selected)
		selected.add_child(UiKit.abs_label("选中", 16, UiKit.COL_TEXT, Rect2i(8, 42, 112, 35), HORIZONTAL_ALIGNMENT_CENTER))
		var card := ItemCard.new()
		card.size = Vector2(64, 128)
		card.configure({"definition": catalog.item(&"poison_vial"), "quality": quality})
		var tooltip := card._make_custom_tooltip("") as Control
		tooltip.position = Vector2(860, y)
		canvas.add_child(tooltip)
		card.free()
	canvas.add_child(UiKit.abs_label("边角固定，边线延展；选中保留品质色。卡面与悬停共用同一套资源。", 16,
		UiKit.COL_MUTED, Rect2i(40, 855, 1350, 28)))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://../outputs/item-frame-templates.png")
		quit(0 if result == OK else 1)
