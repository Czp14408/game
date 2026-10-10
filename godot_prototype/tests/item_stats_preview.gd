extends SceneTree

func _initialize() -> void:
	call_deferred("show_preview")

func show_preview() -> void:
	root.content_scale_size = Vector2i(1200, 760)
	root.size = root.content_scale_size
	DisplayServer.window_set_size(root.size)
	var canvas := Control.new()
	canvas.theme = UiKit.make_theme()
	root.add_child(canvas)
	canvas.add_child(UiKit.overlay(GamePalette.BACKGROUND, Vector2(root.size)))
	canvas.add_child(UiKit.abs_label("现有物品尺寸 · 顶部单排 · 五位数上限 · 字号自适应", 25, GamePalette.TEXT, Rect2i(36, 18, 1150, 44)))
	var source := ContentCatalog.load_default().item(&"poison_vial")
	var poison := ItemCard.new()
	poison.position = Vector2(65, 120)
	poison.size = Vector2(56, 112)
	poison.configure({"definition": source, "quality": 0})
	canvas.add_child(poison)
	canvas.add_child(UiKit.abs_label("砒霜 · 3", 16, GamePalette.TEXT, Rect2i(36, 256, 170, 30)))
	var examples := [[1, 3], [1, 25], [1, 99999], [2, 99999], [3, 99999]]
	var positions := [230, 410, 590, 770, 980]
	for index in examples.size():
		var span: int = examples[index][0]
		var definition := ItemDef.new()
		definition.display_name = "布局示例"
		definition.size = span
		definition.effects = []
		definition.tier_multicast = PackedInt32Array([2, 2, 2, 2]) if index < 2 else PackedInt32Array([10, 10, 10, 10])
		var kinds := ["attack", "shield", "poison"] if span == 1 else GamePalette.STAT_ORDER
		for kind in kinds:
			var effect := EffectDef.make(StringName(kind), &"enemy")
			effect.value_source = &"fixed"
			effect.fixed_value = examples[index][1]
			definition.effects.append(effect)
		if index in [1, 3]:
			definition = (load("res://tests/fixtures/combined_small.tres") if index == 1 else load("res://tests/fixtures/combined_medium.tres")).duplicate(true) as ItemDef
		var card := ItemCard.new()
		card.position = Vector2(positions[index], 120)
		card.size = Vector2(56 * span, 112)
		card.configure({"definition": definition, "quality": 2})
		canvas.add_child(card)
		canvas.add_child(UiKit.abs_label(["小 · 一位数 ×2", "小 · 独立三属性 ×2", "小 · 五位数 ×10", "中 · 独立五属性 ×10", "大 · 五位数 ×10"][index], 16,
			GamePalette.TEXT, Rect2i(positions[index]-20, 256, 210, 30)))
	canvas.add_child(UiKit.abs_label("五位数完整显示；极窄小卡的三属性极限字号很小，悬停可查看清晰的完整数值。", 17, GamePalette.MUTED, Rect2i(36, 330, 1140, 36)))
	canvas.add_child(UiKit.abs_label("美术总调色板：128 色（sRGB）", 22, GamePalette.TEXT, Rect2i(36, 405, 1100, 36)))
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/palettes/game-128-v1.json"))
	for index in palette["colors"].size():
		var swatch := ColorRect.new()
		swatch.position = Vector2(36 + (index % 16) * 71, 464 + (index / 16) * 27)
		swatch.size = Vector2(64, 22)
		swatch.color = Color(palette["colors"][index])
		canvas.add_child(swatch)
	canvas.add_child(UiKit.abs_label("固定顺序：攻击、护盾、中毒、灼烧、回复；图标与属性名称保留在悬停说明。", 16,
		GamePalette.MUTED, Rect2i(36, 705, 1140, 30)))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		quit(0 if root.get_texture().get_image().save_png("res://../outputs/item-stat-palette-preview.png") == OK else 1)
