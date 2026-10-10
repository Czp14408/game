extends Node
## 应用启动入口：加载内容目录、执行参数检查，然后交给 AppRoot 装配界面。
## 边界：本文件只负责启动顺序，不承载业务规则。
##
## 额外命令行（在 `--` 之后传入）：
##   --auto-demo [种子]        在真实帧循环下自动走通整局，用于导出前集成检查。
##   --screenshots [输出目录]  真实渲染下逐页截图并做布局断言（无画面模式覆盖不到）。

const USE_UI := true
const AUTOPLAY_SCRIPT := "res://tests/ui_autoplay.gd"


func _ready() -> void:
	var catalog := ContentCatalog.load_default()
	var problems := catalog.validate()
	print("[原型] 内容版本 %s：%d 物品 / %d 技能 / %d 职业血统 / %d 敌人 / %d 商店 / %d 世界 / %d 阶段集合"
		% [catalog.content_version, catalog.items.size(), catalog.skills.size(), catalog.traits.size(),
			catalog.enemies.size(), catalog.shops.size(), catalog.worlds.size(), catalog.stage_sets.size()])
	if problems.is_empty():
		print("[原型] 参数检查通过")
	else:
		print("[原型] 参数检查发现 %d 项问题：" % problems.size())
		for p in problems:
			print("  - %s" % p)

	if OS.get_cmdline_user_args().has("--auto-demo"):
		var demo: Node = load(AUTOPLAY_SCRIPT).new()
		demo.name = "Autoplay"
		add_child(demo)
		return

	if OS.get_cmdline_user_args().has("--preview-items"):
		if not problems.is_empty():
			get_tree().quit(1)
			return
		var hub: Control = load("res://tests/item_preview_hub.gd").new()
		hub.set("catalog", catalog)
		get_tree().root.add_child.call_deferred(hub)
		return

	if OS.get_cmdline_user_args().has("--preview-item"):
		var preview: Node = load("res://tests/item_preview.gd").new()
		preview.set("catalog", catalog)
		add_child(preview)
		return

	if OS.get_cmdline_user_args().has("--screenshots"):
		var shots: Node = load("res://tests/ui_screenshots.gd").new()
		shots.name = "Screenshots"
		add_child(shots)
		return

	if USE_UI:
		var app := AppRoot.new()
		app.name = "AppRoot"
		app.catalog = catalog
		# 必须挂到视口根节点下：Control 的锚点只有相对视口或父 Control 才会随窗口尺寸变化，
		# 挂在普通 Node（本场景根）下会保持 0×0，导致整棵界面按最小尺寸排布。
		get_tree().root.add_child.call_deferred(app)
