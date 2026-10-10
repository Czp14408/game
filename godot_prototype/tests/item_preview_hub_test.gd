extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var catalog := ContentCatalog.load_default()
	var hub: Control = load("res://tests/item_preview_hub.gd").new()
	hub.set("catalog",catalog)
	hub.set("selected_id",&"poison_vial")
	root.add_child(hub)
	check(hub.get("selected_id") == &"poison_vial","配置表物品优先显示")
	check(hub.get("cards").size() == 4,"四品质预览不依赖自然渠道范围")
	for quality in range(4):
		check(hub.get("cards")[quality].final_value() == (quality+1)*3,"品质数值真实读取定义")
	hub.call("_filter_items","砒霜")
	check(hub.get("filtered_ids").size() == 1,"支持中文名称搜索")
	hub.call("_filter_items","missing_id")
	check(hub.get("selected_id") == &"" and hub.get("battle_button").disabled and hub.get("shop_button").disabled,"找不到物品时禁用验收入口")
	hub.call("_filter_items","POISON_VIAL")
	check(hub.get("selected_id") == &"poison_vial","ID 搜索忽略大小写")
	check(not hub.call("select_item",&"missing_id"),"未知 ID 不替换当前选择")
	hub.call("_start_battle")
	for step in range(29): hub.call("_advance_step")
	for engine in hub.get("engines"):
		check(engine.player_actor().items[0].uses == 0,"实战演示 CD 到期前不释放")
	hub.call("_advance_step")
	for quality in range(4):
		var engine: CombatEngine = hub.get("engines")[quality]
		check(engine.enemy_actor().total_poison() == (quality+1)*3,"四品质独立引擎结算中毒")
		check(hub.get("cards")[quality].motion != null,"实战演示复用已验收状态动效")
	if "--capture" in OS.get_cmdline_user_args():
		hub.set("playing",false)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../outputs/item-preview-battle.png") == OK,"保存战斗预览真实画面")
		hub.set("playing",true)
	for step in range(70): hub.call("_advance_step")
	check(not hub.get("playing") and hub.get("preview_step") == 100,"十秒结束，不继续推进")
	hub.call("_start_battle")
	check(hub.get("engines")[0].player_actor().items[0].uses == 0,"重新播放生成干净战斗状态")
	hub.call("_filter_items","")
	check(hub.get("engines").is_empty() and not hub.get("playing"),"切换搜索关闭旧战斗")
	check(hub.call("select_item",&"short_blade"),"已迁移的旧物品也可预览")
	hub.call("select_item",&"poison_vial")
	hub.call("open_shop_preview")
	for frame in range(4): await process_frame
	var app: AppRoot
	for node in root.get_children():
		if node is AppRoot: app = node
	check(app != null,"购买验收进入正式界面组件")
	if app != null:
		var shop := app.controller.current_shop()
		check(shop != null and shop.slots.size() == 4,"固定商店有四品质商品")
		check(app.controller.buy_slot(0).success,"测试资金支持正式购买流程")
		(app.get_node("PreviewReturn") as Button).pressed.emit()
		for frame in range(3): await process_frame
		var restored: Control
		for node in root.get_children():
			if node.get_script() == load("res://tests/item_preview_hub.gd"): restored = node
		check(restored != null and restored.get("selected_id") == &"poison_vial","从正式购买页返回选中物品")
		if restored != null: restored.queue_free()
	await process_frame
	print("通用预览验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
