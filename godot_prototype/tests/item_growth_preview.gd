extends SceneTree
func _initialize() -> void:
	call_deferred("show_preview")

func show_preview() -> void:
	root.content_scale_size = Vector2i(1000,560)
	root.size = root.content_scale_size
	DisplayServer.window_set_size(root.size)
	var canvas := Control.new()
	canvas.theme = UiKit.make_theme()
	root.add_child(canvas)
	canvas.add_child(UiKit.overlay(GamePalette.BACKGROUND,Vector2(root.size)))
	canvas.add_child(UiKit.abs_label("成长攻击 · Excel → 战斗 → 卡面",25,GamePalette.TEXT,Rect2i(30,20,940,40)))
	canvas.add_child(UiKit.abs_label("青铜铁刃：基础攻击 8，每次使用先使所有己方武器攻击 +5，冷却 2 秒。",17,GamePalette.MUTED,Rect2i(30,65,940,36)))
	var catalog := ContentCatalog.load_default()
	for index in range(4):
		var blade := (load("res://tests/fixtures/growth_blade.tres") as ItemDef).duplicate(true) as ItemDef
		if index == 3: blade.tier_multicast = PackedInt32Array([2,2,2,2])
		catalog.items[blade.definition_id] = blade
		var player := CombatEngine.build_actor(catalog,{"max_hp":10000,"items":[{"definition_id":"growth_blade"}]})
		var enemy := CombatEngine.build_actor(catalog,{"side":1,"max_hp":10000})
		var engine := CombatEngine.new()
		engine.catalog = catalog
		engine.rng = RandomService.create(1)
		engine.begin(player,enemy,"preview","preview")
		for step in [0,20,40,20][index]: engine.step()
		var card := ItemCard.new()
		card.position = Vector2(80+index*240,145)
		card.size = Vector2(112,112)
		card.configure({"definition":blade,"quality":0,"battle_state":player.items[0]})
		canvas.add_child(card)
		canvas.add_child(UiKit.abs_label(["尚未使用","第 1 次使用后","第 2 次使用后","多重释放 ×2 后"][index],18,GamePalette.TEXT,Rect2i(40+index*240,290,230,30)))
		canvas.add_child(UiKit.abs_label("累计攻击：%d" % player.items[0].damage_attack,16,GamePalette.MUTED,Rect2i(40+index*240,325,230,30)))
	canvas.add_child(UiKit.abs_label("×2 本轮分别攻击 13、18，合计 31；卡面显示最终单次攻击 18。",19,GamePalette.TEXT,Rect2i(30,395,940,36)))
	canvas.add_child(UiKit.abs_label("同轮所有成长先结算，包含自身和未就绪武器；成长仅本场战斗有效。",17,GamePalette.MUTED,Rect2i(30,440,940,36)))
	canvas.add_child(UiKit.abs_label("悬停卡片可查看自动生成说明。此示例无物品插画，不进入正式商店。",16,GamePalette.MUTED,Rect2i(30,490,940,36)))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		quit(0 if root.get_texture().get_image().save_png("res://../outputs/item-growth-preview.png") == OK else 1)
