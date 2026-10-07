extends Node
## 自动演示：在真实帧循环（含物理与页面 _process）下走通整局，用于导出前的集成检查。
## 用法：godot --headless --path . -- --auto-demo [种子]
## 边界：只调用控制器与页面公开接口；不写入任何正式数值。

var app: AppRoot
var _fail := 0
var _steps := 0


func _ready() -> void:
	# 延后一帧启动：启动阶段父节点仍在安装子节点，直接 add_child 到 root 会失败
	call_deferred("_begin")


func _begin() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--auto-demo")
	var seed_value := 20261007
	if idx >= 0 and idx + 1 < args.size() and args[idx + 1].is_valid_int():
		seed_value = int(args[idx + 1])
	await _start(seed_value)


func _start(seed_value: int) -> void:
	var catalog := ContentCatalog.load_default()
	app = AppRoot.new()
	app.name = "AutoplayAppRoot"
	app.catalog = catalog
	get_tree().root.add_child(app)
	app.setup(catalog)

	var ctrl := app.controller
	DevTools.mode = DevTools.MODE_RANDOM
	DevTools.world_seed = seed_value

	_ok(ctrl.new_trial(&"warrior", &"sturdy", seed_value), "开局")
	_expect(app.current_page_node() is PageMinimap, "开局进入小地图")

	# 真实物理移动：按住方向键，触发 Area2D 接触与移动边界
	await _move(0.5, "move_right")
	await _move(0.4, "move_up")
	await _move(0.3, "move_left")

	# 入口弱敌筹资
	var keys := ctrl.node_enemy_keys()
	_expect(keys.size() > 0, "入口存在可选敌人")
	if keys.size() > 0:
		ctrl.open_pre_battle(keys[0])
		_expect(app.current_page_node() is PagePreBattle, "进入战前")
		_ok(ctrl.confirm_battle(), "开始战斗")
		_expect(app.current_page_node() is PageBattle, "进入战斗页面")
		await _wait_battle_end(20.0)
		_expect(app.current_page_node() is PagePostBattle, "战斗结束进入战后")
		var es := ctrl.encounter_state()
		if es != null and not es.pending_skill.is_empty():
			ctrl.resolve_skill_drop(true)
		ctrl.pickup_drops()
		ctrl.leave_post_battle()
		_expect(app.current_page_node() is PageMinimap, "离开战后")

	# 付费探索与商店
	_ok(ctrl.travel_to("02"), "进入 02")
	_ok(ctrl.travel_to("03"), "进入 03")
	ctrl.open_build(RunController.PAGE_MINIMAP)
	_expect(app.current_page_node() is PageBuild, "构筑页面")
	ctrl.close_build()
	ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP)
	_expect(app.current_page_node() is PageShop, "商店页面")
	var shop := ctrl.current_shop()
	if shop != null:
		for i in shop.slots.size():
			if ctrl.state.money >= ctrl.economy.price_of_slot(shop.slots[i]):
				ctrl.buy_slot(i)
				break
	ctrl.refresh_shop()
	ctrl.toggle_shop_lock()
	ctrl.toggle_shop_lock()
	ctrl.close_shop()
	ctrl.open_world_map()
	_expect(app.current_page_node() is PageWorldMap, "大地图页面")
	ctrl.close_world_map()

	# 回归、整备与阶段挑战
	ctrl.state.main_completed = true
	_ok(ctrl.return_to_deity(), "回归主神空间")
	_expect(app.current_page_node() is PageDeity, "主神整备页面")
	ctrl.deity_heal()
	ctrl.open_stage_preview()
	_expect(app.current_page_node() is PageStagePreview, "阶段战前页面")
	ctrl.open_build(RunController.PAGE_STAGE_PREVIEW)
	ctrl.close_build()
	_ok(ctrl.confirm_stage_battle(), "开始阶段战斗")
	_expect(app.current_page_node() is PageBattle, "阶段战斗页面")
	var stage_page := app.current_page_node() as PageBattle
	if stage_page != null:
		stage_page.fast_forward()
	await _idle(0.2)
	_expect(app.current_page_node() is PageResult or app.current_page_node() is PageDeity, "阶段结算落地")
	if ctrl.state.is_running():
		ctrl.surrender()
	_expect(app.current_page_node() is PageResult, "结果页面")

	ctrl.start_new_app()
	_expect(app.current_page_node() is PageHome, "重新开局")

	print("[自动演示] 步骤 %d，断言失败 %d" % [_steps, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _expect(cond: bool, label: String) -> void:
	_steps += 1
	if cond:
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)


func _ok(r: OperationResult, label: String) -> void:
	_expect(r.success, "%s%s" % [label, "" if r.success else "（%s）" % r.reason])


func _move(seconds: float, action: String) -> void:
	Input.action_press(action)
	await _idle(seconds)
	Input.action_release(action)
	await _idle(0.05)


func _idle(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.01)).timeout


func _wait_battle_end(timeout: float) -> void:
	var waited := 0.0
	while waited < timeout and app.current_page_node() is PageBattle:
		await _idle(0.1)
		waited += 0.1
		var page := app.current_page_node() as PageBattle
		if page != null:
			page.set("_rate", 4.0)
