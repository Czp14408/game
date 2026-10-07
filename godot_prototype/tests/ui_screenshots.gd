extends Node
## 真实渲染下的界面临界验证：逐页截图，并断言「界面根铺满视口、页面撑满宽度、内容不被压到最小宽度」。
##
## 用法：godot --path . -- --screenshots [输出目录]
## 退出码：0 全部通过；1 存在失败。
##
## 为什么需要它：无画面（--headless）用的是 dummy 渲染驱动，拿不到视口尺寸，
## 也无法发现「根节点尺寸为 0、所有页面只按最小宽度排布」这类只在真实窗口下暴露的问题。
## 历史上正是这一缺陷让界面右侧留白、栏目被压窄、文字一字一行。

const DEFAULT_DIR := "user://screenshots"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]

var app: AppRoot
var _out_dir := DEFAULT_DIR
var _passed := 0
var _failed := 0


func _ready() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--screenshots")
	if idx >= 0 and idx + 1 < args.size() and not args[idx + 1].begins_with("--"):
		_out_dir = args[idx + 1]
	var absolute := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(absolute)

	var catalog := ContentCatalog.load_default()
	app = AppRoot.new()
	app.name = "ScreenshotAppRoot"
	app.catalog = catalog
	get_tree().root.add_child(app)
	app.setup(catalog)

	var ctrl := app.controller
	DevTools.mode = DevTools.MODE_RANDOM
	DevTools.world_seed = 20261007

	for res in RESOLUTIONS:
		await _set_size(res)
		var tag := "%dx%d" % [res.x, res.y]

		await _capture("01_home_%s" % tag, ctrl, "开局选择")

		ctrl.new_trial(&"warrior", &"sturdy", 20261007)
		await _capture("02_minimap_%s" % tag, ctrl, "小地图")

		# 四方向行进指示物对照：直接驱动指示物再截图。
		# 无画面断言只能证明「拿到了正确的纹理」，方向是否真的朝对、镜像版是否可用
		# 仍要看图；这里把四个方向各留一张证据。
		var mini := app.current_page_node() as PageMinimap
		if mini != null:
			for dir in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
				mini.drive_hero(dir, 0.22)
				await _snapshot("02b_walk_%s_%s" % [String(mini.hero_indicator()["direction"]), tag])
			mini.drive_hero(Vector2.ZERO, 0.0)

		var keys := ctrl.node_enemy_keys()
		if keys.size() > 0:
			ctrl.open_pre_battle(keys[0])
			await _capture("03_pre_battle_%s" % tag, ctrl, "战前查看")
			ctrl.confirm_battle()
			await _capture("04_battle_%s" % tag, ctrl, "自动战斗")
			var waited := 0.0
			while waited < 30.0 and app.current_page_node() is PageBattle:
				var page := app.current_page_node() as PageBattle
				if page != null:
					page.set("_rate", 8.0)
				await _idle(0.15)
				waited += 0.15
			await _capture("05_post_battle_%s" % tag, ctrl, "战后反馈")
			var es := ctrl.encounter_state()
			if es != null and not es.pending_skill.is_empty():
				ctrl.resolve_skill_drop(true)
			ctrl.pickup_drops()
			ctrl.leave_post_battle()

		ctrl.travel_to("02")
		ctrl.travel_to("03")
		ctrl.open_build(RunController.PAGE_MINIMAP)
		await _capture("06_build_%s" % tag, ctrl, "构筑与整理")
		ctrl.close_build()
		ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP)
		await _capture("07_shop_%s" % tag, ctrl, "商店交易")
		ctrl.close_shop()
		ctrl.open_world_map()
		await _capture("08_world_map_%s" % tag, ctrl, "大地图")
		ctrl.close_world_map()

		ctrl.state.main_completed = true
		ctrl.return_to_deity()
		await _capture("09_deity_%s" % tag, ctrl, "主神整备")
		ctrl.open_stage_preview()
		await _capture("10_stage_preview_%s" % tag, ctrl, "阶段战前")
		ctrl.cancel_stage_preview()
		ctrl.surrender()
		await _capture("11_result_%s" % tag, ctrl, "试炼结果")

		# 三种结局立绘对照：只构造结果页用于截图，不进入任何结局流程，也不改玩法状态。
		for item in [
			["12_result_victory", "stage_complete", "击败阶段试炼者"],
			["13_result_defeat", "failed", "累计三次战败"],
			["14_result_surrender", "surrendered", "主动认输"],
		]:
			var summary: Dictionary = ctrl.state.summary()
			summary["state"] = item[1]
			app.show_page(PageResult.new(ctrl, {"summary": summary, "reason": item[2]}))
			await _snapshot("%s_%s" % [item[0], tag])

		ctrl.start_new_app()

	print("[界面截图验证] 通过 %d，失败 %d，输出 %s" % [_passed, _failed, absolute])
	get_tree().quit(1 if _failed > 0 else 0)


func _set_size(res: Vector2i) -> void:
	DisplayServer.window_set_size(res)
	await get_tree().process_frame
	await get_tree().process_frame
	await _idle(0.2)


## 截图 + 布局断言。布局检查基于真实视口尺寸，是无画面测试覆盖不到的部分。
func _capture(name: String, ctrl: RunController, label: String) -> void:
	await _idle(0.2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_check(img.save_png("%s/%s.png" % [_out_dir, name]) == OK, "%s 截图已保存" % label)

	var page := app.current_page_node()
	_check(page != null, "%s：页面在位" % label)
	if page == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_check(app.size.x >= vp.x - 1.0 and app.size.y >= vp.y - 1.0,
		"%s：界面根铺满视口（%.0f×%.0f / %.0f×%.0f）" % [label, app.size.x, app.size.y, vp.x, vp.y])
	_check(page.size.x >= vp.x - 1.0,
		"%s：页面撑满宽度（%.0f / %.0f）" % [label, page.size.x, vp.x])
	var content := _first_content_width(page)
	_check(content >= page.size.x - 1.0,
		"%s：页面内容未被压到最小宽度（%.0f / %.0f）" % [label, content, page.size.x])


## 只截图、不重复跑布局断言。用于同一页面下的多处对照（四方向指示物、三种结局立绘）。
func _snapshot(name: String) -> void:
	await _idle(0.15)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_check(img.save_png("%s/%s.png" % [_out_dir, name]) == OK, "%s 截图已保存" % name)


## 页面第一层内容容器的实际宽度：若被压到最小宽度，说明锚点或滚动容器标记有问题。
func _first_content_width(page: Control) -> float:
	for ch in page.get_children():
		if ch is VBoxContainer:
			return (ch as Control).size.x
		if ch is Control:
			return (ch as Control).size.x
	return 0.0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ✓ %s" % label)
	else:
		_failed += 1
		print("  ✗ %s" % label)


func _idle(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.01)).timeout
