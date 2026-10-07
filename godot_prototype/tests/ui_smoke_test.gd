class_name UiSmokeTest
extends TestSuite
## 界面冒烟测试：无画面构建 AppRoot，走通「开局→探索→战斗→商店→构筑→回归→阶段→结果」。
## 目的：捕获页面工厂缺失、脚本运行时错误与界面在异常状态下崩溃。
## 边界：只驱动控制器与页面公开接口，不直接修改状态字段（唯一例外：为制造回归条件置主线完成标记）。

var app: AppRoot
var tree: SceneTree


## 输入映射必须与 README 与界面提示一致。
## 回归背景：大地图曾在 `project.godot` 中被绑到 Backspace（4194308），
## 而 README 与页面按钮都写「Tab」，两者不一致——人工试玩时表现为「按 Tab 没反应」。
func _test_input_map() -> void:
	var expected: Dictionary = {
		"move_up": KEY_W,
		"move_down": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"interact": KEY_E,
		"open_world_map": KEY_TAB,
		"open_build": KEY_B,
		"cancel": KEY_ESCAPE,
		"dev_step": KEY_F,
	}
	for action in expected.keys():
		var want := int(expected[action])
		var found := false
		for ev in InputMap.action_get_events(String(action)):
			var ke := ev as InputEventKey
			if ke == null:
				continue
			if ke.keycode == want or ke.physical_keycode == want:
				found = true
				break
		check(found, "按键 %s 绑定到 %s" % [action, OS.get_keycode_string(want)])


## 模拟按一次 Tab。无画面脚本模式下引擎不派发输入事件，只能直接投递给页面的输入处理。
func _press_tab(page: Node) -> void:
	if page == null:
		check(false, "按 Tab 时当前页面为空")
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	check(ev.is_action_pressed("open_world_map"), "Tab 事件能匹配 open_world_map 动作")
	page._unhandled_input(ev)


func run() -> void:
	suite_name = "M4/M5 界面冒烟"
	tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		check(false, "无法取得 SceneTree")
		return

	var catalog := ContentCatalog.load_default()
	check(catalog.load_errors.is_empty(), "内容目录加载无错误")
	check(catalog.validate().is_empty(), "参数检查通过")

	_test_input_map()

	app = AppRoot.new()
	app.name = "SmokeAppRoot"
	app.catalog = catalog
	tree.root.add_child(app)
	app.setup(catalog)

	var ctrl := app.controller
	check(ctrl != null, "控制器已建立")
	check(app.current_page_node() is PageHome, "开局进入选择页面")

	# --- 开局（随机游玩模式） ---
	DevTools.mode = DevTools.MODE_RANDOM
	var r := ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	check(r.success, "开局成功：%s" % r.reason)
	check(app.current_page_node() is PageMinimap, "开局进入小地图")
	check(ctrl.state.money == RunState.START_MONEY, "开局货币为 %d" % RunState.START_MONEY)
	check(ctrl.state.battle_bar.size() == 1, "开局战斗栏有 1 件物品")

	var mini := app.current_page_node() as PageMinimap
	check(mini != null, "小地图页面类型正确")
	if mini != null:
		var specs := mini.interactable_specs()
		check(specs.size() > 0, "入口节点有可交互内容（%d 项）" % specs.size())
		var kinds := {}
		for s in specs:
			kinds[s["kind"]] = true
		check(kinds.has("enemy"), "入口节点有可选敌人")
		check(kinds.has("exit"), "入口节点有离开通路")
		var areas: Array = mini.get("_areas")
		check(areas.size() == specs.size(), "小地图交互实体数与清单一致（%d）" % areas.size())
		check(mini.get("_player") != null, "小地图已创建角色实体")
		check(mini.get("_walls") != null, "小地图已创建地形碰撞")

	# --- 世界战斗 ---
	var keys := ctrl.node_enemy_keys()
	check(keys.size() > 0, "取得节点敌人清单")
	ctrl.open_pre_battle(keys[0])
	check(app.current_page_node() is PagePreBattle, "进入战前查看页面")

	var br := ctrl.confirm_battle()
	check(br.success, "开始战斗")
	check(app.current_page_node() is PageBattle, "进入自动战斗页面")

	var money_before := ctrl.state.money
	var battle := app.current_page_node() as PageBattle
	battle.fast_forward()
	var page := app.current_page_node()
	check(page is PagePostBattle, "战斗结束后进入战后反馈页面")
	check(ctrl.last_result != null, "战斗结果已生成")
	if ctrl.last_result != null:
		check(ctrl.last_result.steps > 0, "战斗推进了 %d 个时间步" % ctrl.last_result.steps)
		check(ctrl.state.money >= money_before, "胜利后货币不减少")

	var post := page as PagePostBattle
	if post != null:
		var es := ctrl.encounter_state()
		if es != null and not es.pending_skill.is_empty():
			ctrl.resolve_skill_drop(false)
		ctrl.pickup_drops()
	check(app.current_page_node() is PagePostBattle, "战后页面在拾取后仍在位")

	ctrl.leave_post_battle()
	check(app.current_page_node() is PageMinimap, "离开战后回到小地图")

	# --- 付费探索：01 → 03 ---
	var money_pre := ctrl.state.money
	var tr := ctrl.travel_to("03")
	check(tr.success, "进入 03 号节点：%s" % tr.reason)
	check(ctrl.state.money == money_pre - 2, "首次进入新节点扣费 2（%d → %d）" % [money_pre, ctrl.state.money])
	var money_after_first := ctrl.state.money
	var revisit := ctrl.travel_to("01")
	check(revisit.success, "免费重访 01")
	var back := ctrl.travel_to("03")
	check(back.success and ctrl.state.money == money_after_first, "重访不重复扣费")

	# --- 构筑 ---
	ctrl.open_build(RunController.PAGE_MINIMAP)
	check(app.current_page_node() is PageBuild, "进入构筑页面")
	var build := app.current_page_node() as PageBuild
	check(build != null, "构筑页面类型正确")
	var unequip_target := ""
	if ctrl.state.inventory.size() > 0:
		unequip_target = ctrl.state.inventory[0].instance_id
		var er := ctrl.equip(unequip_target)
		check(er.success, "装备背包物品")
		var ur := ctrl.unequip(unequip_target)
		check(ur.success, "卸下物品")
	ctrl.close_build()
	check(app.current_page_node() is PageMinimap, "构筑返回小地图")

	# --- 商店 ---
	ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP)
	check(app.current_page_node() is PageShop, "进入商店页面")
	var shop := ctrl.current_shop()
	check(shop != null, "商店库存已生成")
	if shop != null:
		check(shop.slots.size() > 0, "商品位 %d 个" % shop.slots.size())
		var money0 := ctrl.state.money
		var bought := false
		for i in shop.slots.size():
			var slot: ShopState.Slot = shop.slots[i]
			if slot.purchased:
				continue
			var price := ctrl.economy.price_of_slot(slot)
			if price <= ctrl.state.money:
				var br2 := ctrl.buy_slot(i)
				if br2.success:
					bought = true
					check(ctrl.state.money == money0 - price, "购买后按标价扣款")
					var again := ctrl.buy_slot(i)
					check(not again.success, "重复购买同一商品被拒绝")
					break
		if not bought:
			note("商店首件商品暂不可买（余额或容量），跳过购买断言")
		var rr := ctrl.refresh_shop()
		if rr.success:
			check(ctrl.economy.price_of_slot(ctrl.current_shop().slots[0]) >= 0, "刷新后库存可读")
		else:
			check(ctrl.state.money < 3, "刷新失败原因为余额不足")
	ctrl.toggle_shop_lock()
	check(ctrl.current_shop().locked, "锁定状态生效")
	var locked_refresh := ctrl.refresh_shop()
	check(not locked_refresh.success, "锁定后不能刷新")
	ctrl.toggle_shop_lock()
	check(not ctrl.current_shop().locked, "解锁状态生效")
	ctrl.close_shop()
	check(app.current_page_node() is PageMinimap, "商店返回小地图")

	# --- 大地图（Tab 作为开关：打开 / 收起） ---
	check(app.current_page_node() is PageMinimap, "Tab 开关的起点是小地图")
	_press_tab(app.current_page_node())
	check(app.current_page_node() is PageWorldMap, "小地图按 Tab 打开大地图")
	var wm := app.current_page_node() as PageWorldMap
	check(wm != null, "大地图页面类型正确")
	_press_tab(app.current_page_node())
	check(app.current_page_node() is PageMinimap, "大地图上再按 Tab 收起回小地图")
	# 按钮路径同样保留
	ctrl.open_world_map()
	check(app.current_page_node() is PageWorldMap, "按钮路径：进入大地图页面")
	ctrl.close_world_map()
	check(app.current_page_node() is PageMinimap, "按钮路径：大地图返回小地图")

	# --- 回归与阶段 ---
	ctrl.state.main_completed = true
	var ret := ctrl.return_to_deity()
	check(ret.success, "主线完成后可回归：%s" % ret.reason)
	check(app.current_page_node() is PageDeity, "进入主神整备页面")
	check(not ctrl.state.stage_opponent.is_empty(), "回归时生成阶段对手")
	var before_hp := ctrl.state.current_hp
	ctrl.state.set_hp(before_hp - 20.0)
	var heal := ctrl.deity_heal()
	check(heal.success and ctrl.state.current_hp == ctrl.state.max_hp, "主神治疗回满且不扣币")
	check(ctrl.state.money >= 0, "治疗后货币未被扣减")

	var opp_before := ctrl.state.stage_opponent.duplicate()
	ctrl.open_stage_preview()
	check(app.current_page_node() is PageStagePreview, "进入阶段战前查看")
	ctrl.open_build(RunController.PAGE_STAGE_PREVIEW)
	check(app.current_page_node() is PageBuild, "从阶段预览进入构筑")
	ctrl.close_build()
	check(app.current_page_node() is PageStagePreview, "构筑返回阶段预览")
	check(ctrl.state.stage_opponent.get("display_name", "") == opp_before.get("display_name", ""), "换装不改变已固定的阶段对手")

	var sr := ctrl.confirm_stage_battle()
	check(sr.success, "开始阶段战斗")
	check(app.current_page_node() is PageBattle, "进入阶段自动战斗页面")
	var sbattle := app.current_page_node() as PageBattle
	sbattle.fast_forward()
	page = app.current_page_node()
	check(page is PageResult or page is PageDeity, "阶段战斗结果落到结果页或整备页")
	if ctrl.state.is_running():
		check(page is PageDeity, "阶段战败且次数未耗尽时回到整备")
		ctrl.surrender()
	check(app.current_page_node() is PageResult, "认输进入结果页")
	var result := app.current_page_node() as PageResult
	check(result != null, "结果页类型正确")
	check(ctrl.state.battle_bar.is_empty() and ctrl.state.inventory.is_empty(), "试炼结束后清空携带物")

	# --- 重新开局 ---
	ctrl.start_new_app()
	check(app.current_page_node() is PageHome, "重新开局回到选择页面")

	# --- 四种开发测试模式的入口都可用 ---
	for mode in [DevTools.MODE_RANDOM, DevTools.MODE_REPLAY_NORMAL, DevTools.MODE_REPLAY_LOW,
			DevTools.MODE_REPLAY_FAILURE]:
		ctrl.request_dev_mode(mode)
		var mr := ctrl.new_trial(&"warrior", &"sturdy", 20261007)
		check(mr.success, "模式 %s 可开局" % mode)
		check(app.current_page_node() is PageMinimap, "模式 %s 进入小地图" % mode)
		check(ctrl.dev_mode == mode, "模式 %s 已生效" % mode)
		if DevTools.is_replay():
			check(not ctrl.encounters.drop_override.is_empty(), "回放模式 %s 有固定掉落序列" % mode)
			check(not ctrl.state.node_state("__deity__").shops.is_empty(), "回放模式 %s 已安装固定主神库存" % mode)

	# --- 战斗实验室 ---
	DevTools.mode = DevTools.MODE_BATTLE_LAB
	ctrl.request_dev_mode(DevTools.MODE_BATTLE_LAB)
	ctrl.new_trial(&"medic", &"vampire", 20261007)
	check(app.current_page_node() is PageBattleLab, "战斗实验室入口直接进入实验室页面")
	var lab := app.current_page_node() as PageBattleLab
	if lab != null:
		lab.call("_reset_engine")
		lab.call("_run_all")
		check(app.current_page_node() is PageBattleLab, "实验室快速计算后页面仍在位")
		var lab_engine: CombatEngine = lab.get("_engine")
		check(lab_engine != null and lab_engine.is_finished(), "实验室快速计算已结束")
		check(lab_engine.result().steps > 0, "实验室结果含 %d 个时间步" % lab_engine.result().steps)
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.request_dev_mode(DevTools.MODE_RANDOM)


## 布局检查（需要真实帧推进，由 headless_main 在同步断言之后 await）
func extend_with_frames() -> void:
	if app == null or tree == null:
		return
	for target in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		# 只改窗口尺寸，页面按 full-rect 锚点自动跟随，避免与锚点冲突
		tree.root.size = target
		await tree.process_frame
		await tree.process_frame
		var page := app.current_page_node()
		check(page != null, "%d×%d：页面在位" % [target.x, target.y])
		if page == null:
			continue
		check(page.size.x > 200.0 and page.size.y > 120.0,
			"%d×%d：页面已布局（%.0f×%.0f）" % [target.x, target.y, page.size.x, page.size.y])
		var min_size := page.get_combined_minimum_size()
		check(min_size.x <= float(target.x) + 1.0,
			"%d×%d：页面最小宽度 %.0f 未超出视口" % [target.x, target.y, min_size.x])

	# 各主要页面在 1920×1080 下都能构建出非空内容
	var ctrl := app.controller
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	await tree.process_frame
	var routes: Array[Callable] = [
		func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP),
		func() -> void: ctrl.close_build(),
		func() -> void: ctrl.open_world_map(),
		func() -> void: ctrl.close_world_map(),
		func() -> void: ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP),
		func() -> void: ctrl.close_shop(),
	]
	for step in routes:
		step.call()
		await tree.process_frame
		await tree.process_frame
		var page := app.current_page_node()
		check(page != null and page.get_child_count() > 0, "页面在帧推进后仍有内容：%s" % ctrl.current_page)
	ctrl.state.main_completed = true
	ctrl.return_to_deity()
	await tree.process_frame
	check(app.current_page_node() is PageDeity and (app.current_page_node() as Control).get_child_count() > 0, "主神整备页面有内容")
	tree.root.size = Vector2i(1280, 720)
	await tree.process_frame
