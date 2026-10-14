class_name AppRoot
extends Control
## 界面根节点：装配页面、驱动页面切换、承载全局主题与状态栏。
## 边界：UI 只提交命令并监听状态变化刷新，禁止直接修改金币、生命或物品数组。

var catalog: ContentCatalog
var controller: RunController
var _page_holder: Control
var _status_label: Label
var _pages: Dictionary = {}
var _setup_done := false


func _ready() -> void:
	setup(catalog)


## 装配界面并开始一次新会话。幂等：无画面测试可显式调用，避免依赖 _ready 时机。
func setup(p_catalog: ContentCatalog = null) -> void:
	if _setup_done:
		return
	_setup_done = true
	if p_catalog != null:
		catalog = p_catalog
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if theme == null:
		theme = UiKit.make_theme()
	_build_shell()
	controller = RunController.new()
	controller.catalog = catalog
	controller.page_requested.connect(_on_page_requested)
	controller.message.connect(_on_message)
	register_pages()
	controller.start_new_app()


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.name = "Shell"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_status_label = Label.new()
	_status_label.name = "StatusBar"
	_status_label.custom_minimum_size = Vector2(0, 30)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", UiKit.COL_MUTED)
	_status_label.text = "  加载中……"
	root.add_child(_status_label)

	_page_holder = Control.new()
	_page_holder.name = "PageHolder"
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_page_holder)


func register_pages() -> void:
	_pages[RunController.PAGE_HOME] = func(c: RunController, p: Dictionary) -> Control: return PageHome.new(c, p)
	_pages[RunController.PAGE_MINIMAP] = func(c: RunController, p: Dictionary) -> Control:
		return PageNodeCards.new(c, p) if c.state != null and c.state.card_exploration else PageMinimap.new(c, p)
	_pages[RunController.PAGE_WORLD_MAP] = func(c: RunController, p: Dictionary) -> Control: return PageWorldMap.new(c, p)
	_pages[RunController.PAGE_PRE_BATTLE] = func(c: RunController, p: Dictionary) -> Control: return PagePreBattle.new(c, p)
	_pages[RunController.PAGE_BATTLE] = func(c: RunController, p: Dictionary) -> Control: return PageBattle.new(c, p)
	_pages[RunController.PAGE_POST_BATTLE] = func(c: RunController, p: Dictionary) -> Control: return PagePostBattle.new(c, p)
	_pages[RunController.PAGE_SHOP] = func(c: RunController, p: Dictionary) -> Control: return PageShop.new(c, p)
	_pages[RunController.PAGE_BUILD] = func(c: RunController, p: Dictionary) -> Control: return PageBuild.new(c, p)
	_pages[RunController.PAGE_DEITY] = func(c: RunController, p: Dictionary) -> Control: return PageDeity.new(c, p)
	_pages[RunController.PAGE_STAGE_PREVIEW] = func(c: RunController, p: Dictionary) -> Control: return PageStagePreview.new(c, p)
	_pages[RunController.PAGE_RESULT] = func(c: RunController, p: Dictionary) -> Control: return PageResult.new(c, p)
	_pages[RunController.PAGE_BATTLE_LAB] = func(c: RunController, p: Dictionary) -> Control: return PageBattleLab.new(c, p)


func show_page(page: Control) -> void:
	for child in _page_holder.get_children():
		_page_holder.remove_child(child)
		child.queue_free()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_holder.add_child(page)
	# 显式构建：不依赖引擎 _ready 的派发时机（无画面脚本模式下不会派发）
	if page is PageBase:
		(page as PageBase).ensure_built()


## 当前页面节点（无画面验证与调试使用）
func current_page_node() -> Control:
	if _page_holder.get_child_count() == 0:
		return null
	return _page_holder.get_child(0) as Control


func _on_page_requested(page: StringName, payload: Dictionary) -> void:
	var factory: Callable = _pages.get(page, Callable())
	if factory.is_valid():
		var node: Control = factory.call(controller, payload)
		if node != null:
			show_page(node)
			return
	_on_message("页面 %s 尚未实现" % page)


func _on_message(text: String) -> void:
	_status_label.text = "  " + text


func hud_text() -> String:
	if controller == null or controller.state == null:
		return "未开始试炼"
	var s := controller.state
	return "生命 %d/%d　货币 %d　战败 %d/%d　当前节点 %s" % [
		int(s.current_hp), int(s.max_hp), s.money, s.defeats, RunState.MAX_DEFEATS, s.current_node_id,
	]
