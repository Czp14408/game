class_name PageWorldMap
extends PageBase
## 信息页：左侧世界节点地图，右侧任务、目标与情报，集中在 information_panel 上。
## 依据：游戏主界面与交互调整方案.md §1、§5（信息页保留当前世界名称、左侧世界节点地图、
## 右侧任务/目标/情报）；技术方案第 9 节。
##
## 布局：底板与左右子区（world_map / quests）全部来自 SystemSkin 的 layout.json，
## 本页不写死坐标；页面用绝对定位，只留一个 CenterContainer 承载设计画布。

var _canvas: Control
var _map: MapCanvas
var _map_holder: Control
var _quest_box: Control
var _quest_list: RichTextLabel
var _detail_box: Control
var _detail_head: Label
var _detail_body: Label
var _selected := ""


func build() -> void:
	var center := CenterContainer.new()
	center.name = "WorldMapCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_canvas = Control.new()
	_canvas.name = "DesignCanvas"
	var design := SystemSkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_canvas.custom_minimum_size = Vector2(design)
	center.add_child(_canvas)
	_canvas.add_child(UiKit.solid(UiKit.COL_BG, Rect2i(Vector2i.ZERO, design)))

	# 信息页底板（information_panel）
	var bg := UiKit.abs_sys_panel(SystemSkin.INFORMATION_PANEL, 0.9)
	if bg != null:
		bg.name = "InfoPanel"
		_canvas.add_child(bg)

	_build_map()
	_build_quests()
	_refresh()


## 左侧：世界节点地图（world_map 子区）。
func _build_map() -> void:
	var r := SystemSkin.region_abs(SystemSkin.INFORMATION_PANEL, "world_map")
	_map_holder = Control.new()
	_map_holder.name = "MapHolder"
	_map_holder.position = Vector2(r.position)
	_map_holder.size = Vector2(r.size)
	_map_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_map_holder)

	_map = MapCanvas.new()
	_map.name = "MapCanvas"
	_map.state = ctrl.state
	_map.world_def = ctrl.world.world(ctrl.state)
	_map.world_service = ctrl.world
	_map.catalog = catalog
	_map.position = Vector2.ZERO
	_map.size = Vector2(r.size)
	_map.mouse_filter = Control.MOUSE_FILTER_PASS
	_map.node_clicked.connect(_on_node_clicked)
	_map_holder.add_child(_map)


## 右侧：任务/目标/情报（quests 子区），下方附选中节点详情。
## 列表用 RichTextLabel 自管换行与滚动：ScrollContainer + 自动换行 Label（clip_text）
## 的最小高度会塌成 1 像素，真渲染整块空白——战斗日志踩过同一坑（见 ui_kit.log_text）。
func _build_quests() -> void:
	var r := SystemSkin.region_abs(SystemSkin.INFORMATION_PANEL, "quests")
	_quest_box = Control.new()
	_quest_box.name = "QuestBox"
	_quest_box.position = Vector2(r.position)
	_quest_box.size = Vector2(r.size)
	_quest_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_quest_box)

	# 任务/情报列表（上半）
	_quest_list = UiKit.abs_log(12, UiKit.COL_SYS_TEXT,
		Rect2i(4, 0, int(r.size.x) - 8, int(r.size.y * 0.62)))
	_quest_list.name = "QuestList"
	_quest_box.add_child(_quest_list)

	# 选中节点详情（下半）
	var dy := int(r.size.y * 0.64)
	_detail_box = Control.new()
	_detail_box.name = "DetailBox"
	_detail_box.position = Vector2(4, dy)
	_detail_box.size = Vector2(r.size.x - 8, r.size.y - dy - 4)
	_quest_box.add_child(_detail_box)
	_detail_head = UiKit.abs_sys_label("节点详情", 13,
		Rect2i(0, 0, _detail_box.size.x, 20), UiKit.COL_SYS_ACCENT)
	_detail_box.add_child(_detail_head)
	_detail_body = UiKit.abs_sys_block("", 12,
		Rect2i(0, 22, _detail_box.size.x, _detail_box.size.y - 24), UiKit.COL_SYS_TEXT)
	_detail_body.name = "DetailBody"
	_detail_box.add_child(_detail_body)


func _on_node_clicked(node_id: String) -> void:
	_selected = node_id
	_refresh()


## M/Esc 作为「信息页」开关：小地图按 M 打开，在信息页上再按一次或 Esc 收起。
func _unhandled_input(event: InputEvent) -> void:
	# 页面已脱离界面或正在释放时不再响应输入（不用 is_inside_tree()，理由见 page_minimap.gd）。
	if get_parent() == null or is_queued_for_deletion():
		return
	if event.is_action_pressed("open_world_map") \
			or event.is_action_pressed("cancel"):
		ctrl.close_world_map()
		consume_input()


func _refresh() -> void:
	if _quest_list == null:
		return
	_quest_list.clear()
	var state := ctrl.state
	var w := ctrl.world.world(state)

	_quest_line("当前位置：%s %s" % [state.current_node_id, _node_name(state.current_node_id)],
		14, UiKit.COL_SYS_TEXT)

	if w == null:
		_quest_line("世界缺失", 13, UiKit.COL_SYS_MUTED)
		_refresh_detail()
		return

	# 主线目标优先，支线任务其次
	var qdefs := w.quests.duplicate()
	var main: Array = []
	var side: Array = []
	for qdef in qdefs:
		if qdef.is_main:
			main.append(qdef)
		else:
			side.append(qdef)
	_quest_line("任务与目标", 13, UiKit.COL_SYS_ACCENT)
	for qdef in main + side:
		var qs := state.quest_state(qdef.quest_id)
		var status := "未接取"
		var col := UiKit.COL_SYS_MUTED
		match qs.status:
			QuestState.STATUS_ACCEPTED:
				status = "进行中"
				col = UiKit.COL_SYS_GOOD
			QuestState.STATUS_COMPLETED:
				status = "待领奖"
				col = UiKit.COL_SYS_ACCENT
			QuestState.STATUS_CLAIMED:
				status = "已完成"
		var mark := "主" if qdef.is_main else "支"
		_quest_line("【%s】%s：%s" % [mark, qdef.display_name, status], 12, col)

	# 已获得情报（支持展开）
	_quest_line("情报", 13, UiKit.COL_SYS_ACCENT)
	var intel := PackedStringArray()
	if state.known_intel.has("bandit_area"):
		intel.append("土匪区域位置已知")
	if state.known_intel.has("chief_node"):
		intel.append("头子位置已知")
	if intel.is_empty():
		_quest_line("暂未获得情报", 12, UiKit.COL_SYS_MUTED)
	else:
		for t in intel:
			_quest_line("· %s" % t, 12, UiKit.COL_SYS_TEXT)

	_refresh_detail()


## 往任务/情报列表追加一行（bbcode 上色；文字里不用半角方括号，避免被当标签吞掉）。
func _quest_line(text: String, font_size: int, col: Color) -> void:
	_quest_list.append_text("[color=%s][font_size=%d]%s[/font_size][/color]\n" % [
		col.to_html(false), font_size, text,
	])


func _refresh_detail() -> void:
	if _detail_head == null or _detail_body == null:
		return
	var state := ctrl.state
	if _selected == "":
		_detail_head.text = "节点详情（未选中）"
		_detail_body.text = "点击左侧地图上的节点查看详情。\n\n货币 %d　下一新节点费用 %d" % [
			state.money, ctrl.world.next_fee_preview(state),
		]
		return
	_detail_head.text = "节点 %s %s" % [_selected, _node_name(_selected)]
	var nd := ctrl.world.world(state).node_by_id(_selected)
	var lines := PackedStringArray()
	if nd != null:
		var content := PackedStringArray()
		if not nd.shop_ids.is_empty():
			content.append("%d 家店铺" % nd.shop_ids.size())
		if not nd.enemies.is_empty():
			content.append("%d 个可选敌人" % nd.enemies.size())
		if not nd.npc_services.is_empty():
			content.append("%d 处人物" % nd.npc_services.size())
		if nd.has_container:
			content.append("容器")
		lines.append("类型：%s" % MapLayout.area_name(_selected))
		lines.append("已知内容：%s" % ("、".join(content) if content.size() > 0 else "无"))
	var discovered := state.node_state(_selected).entered
	lines.append("进入过：%s" % ("是（重访免费）" if discovered else "否"))
	var fee := _map.fee_of(_selected)
	lines.append("本次进入费用：%s" % ("免费" if fee == 0 else "%d 货币" % fee))
	if _is_blocked_to(_selected):
		lines.append("该通路被守路者封锁。")
	_detail_body.text = "\n".join(lines)


func _node_name(node_id: String) -> String:
	var nd := ctrl.world.world(ctrl.state).node_by_id(node_id)
	return nd.display_name if nd != null else ""


func _is_blocked_to(node_id: String) -> bool:
	return ctrl.world.is_connection_blocked(ctrl.state, ctrl.state.current_node_id, node_id)


func layout_report() -> Dictionary:
	return {
		"canvas_min": Vector2i(_canvas.custom_minimum_size),
		"canvas": Vector2i(_canvas.size),
		"design": SystemSkin.design_size(),
		"map_region": SystemSkin.region_abs(SystemSkin.INFORMATION_PANEL, "world_map"),
		"quest_region": SystemSkin.region_abs(SystemSkin.INFORMATION_PANEL, "quests"),
		"map_size": Vector2i(_map.size) if _map != null else Vector2i.ZERO,
	}
