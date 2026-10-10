extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := ContentCatalog.load_default()
	var source := catalog.item(&"poison_vial")
	for quality in range(4):
		var normal := ItemSkin.frame_style(quality)
		var selected := ItemSkin.frame_style(quality, true)
		var tooltip := ItemSkin.frame_style(quality, false, true)
		check(normal.texture == tooltip.texture, "同品质物品格与悬停共用资源")
		check(selected.texture != normal.texture, "选中采用独立内框状态")
		check(normal.get_texture_margin(SIDE_LEFT) == 8, "九宫格像素边角固定")
	for span in [1, 2, 3]:
		var definition := source.duplicate() as ItemDef
		definition.size = span
		var card := ItemCard.new()
		card.size = Vector2(56 * span, 112)
		card.configure({"definition": definition, "quality": 1})
		check(is_equal_approx(card.card_rect.size.x / card.card_rect.size.y, span / 2.0), "三种物品宽高比")
		var image := card.frame.get_node("ItemImage") as TextureRect
		check(image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "图片保留完整画面")
		card.free()
	var instance := ItemInstance.make(&"poison_vial", 1)
	instance.trial_growth = 5
	var card := ItemCard.new()
	card.size = Vector2(140, 112)
	card.configure({"definition": source, "quality": 1, "instance": instance, "price_text": "12 货币"})
	check(card.description().contains("[b]11[/b]") and not card.description().contains("成长"), "只显示最终效果数值")
	check(not card.description().contains("白银") and card.description().contains("冷却：3 秒"), "标题不附带品质，冷却单位为秒")
	check(card.description().contains("材料") and card.description().contains("poison.svg"), "TAG 与中毒图标")
	check(is_equal_approx(card.card_rect.size.x / card.card_rect.size.y, 0.5), "商店价格不挤压物品宽高比")
	var battle := BattleItemState.new()
	battle.base_value = 17
	battle.battle_growth = 4
	card.battle_state = battle
	check(card.final_value() == 21, "战斗浮窗读取当前实例数值")
	var popup := card._make_custom_tooltip("") as Control
	battle.battle_growth = 10
	card._process(0)
	check(card.tooltip_body.text.contains("[b]27[/b]"), "悬停期间数值实时更新")
	check((card.stat_layer.get_child(0) as ItemStatBadge).value_text == "27", "卡面数值同步最终属性")
	popup.free()
	card.free()
	var combined := source.duplicate() as ItemDef
	combined.icon_path = ""
	combined.effects = []
	for pair in [["poison", 3], ["shield", 0], ["attack", 25]]:
		var effect := EffectDef.make(StringName(pair[0]), &"enemy")
		effect.value_source = &"fixed"
		effect.fixed_value = pair[1]
		combined.effects.append(effect)
	var compact := ItemCard.new()
	compact.size = Vector2(56, 112)
	compact.configure({"definition": combined, "quality": 0})
	check(compact.stat_layer.get_child_count() == 3, "三种属性同时展示，包括零值")
	check((compact.stat_layer.get_child(0) as ItemStatBadge).kind == "attack", "属性按固定顺序展示")
	check(compact.stat_layer.get_child(0).position.y == compact.stat_layer.get_child(1).position.y, "小卡前两枚属性并列")
	check(compact.stat_layer.get_child(0).position.y < 0, "首排徽章跨在卡面上边框")
	check(compact.stat_layer.get_child(2).position.y == compact.stat_layer.get_child(0).position.y, "三属性始终单排")
	for badge in compact.stat_layer.get_children():
		check(badge.position.x >= 0 and badge.position.x + badge.size.x <= compact.size.x, "属性标记不侵占相邻物品区域")
	check(compact.size == Vector2(56, 112), "物品尺寸由现有槽位决定")
	for effect in combined.effects:
		effect.fixed_value = 99999
	compact._process(0)
	for badge in compact.stat_layer.get_children():
		check(badge.value_text == "99999", "完整显示五位整数")
		var font_size: int = badge.caption.get_theme_font_size("font_size")
		check(badge.caption.get_theme_font("font").get_string_size("99999", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= badge.caption.size.x, "字号自适应保证五位数不裁剪")
		check(font_size < 16, "窄卡数值自动缩小字体")
		check(badge.position.y == -8, "五位数仍然单排")
		check(badge.get_child_count() == 1, "数值前无图标")
		check(badge.position.x >= 0 and badge.position.x + badge.size.x <= compact.size.x, "五位数标记不侵占相邻物品")

	compact.free()
	if "--capture" in OS.get_cmdline_user_args():
		var app := AppRoot.new()
		app.catalog = catalog
		root.add_child(app)
		app.setup(catalog)
		app.controller.new_trial(&"warrior", &"sturdy", 1)
		app.controller.install_fixed_shop("__item_preview__", &"gear_shop", [[&"poison_vial", 0], [&"poison_vial", 1], [&"poison_vial", 2], [&"poison_vial", 3]])
		app.controller.open_shop("__item_preview__/gear_shop")
		var panel: PanelInventory = app.current_page_node().get("_panel")
		var first := panel.cell_by_id(InventorySkin.ROW_A, "goods:1") as ItemCard
		var tooltip := first._make_custom_tooltip("") as Control
		tooltip.position = Vector2(250, 220)
		root.add_child(tooltip)
		for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			DisplayServer.window_set_size(resolution)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://../outputs/item-presentation-%dx%d.png" % [resolution.x, resolution.y]
			check(root.get_texture().get_image().save_png(path) == OK, "保存真实渲染截图")
		tooltip.queue_free()
		app.queue_free()
	print("物品展示验证：通过 %d，失败 %d" % [passed, failed])
	quit(1 if failed else 0)
