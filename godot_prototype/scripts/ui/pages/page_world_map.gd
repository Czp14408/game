class_name PageWorldMap
extends PageBase
## 大地图：18 节点与双向连接，显示当前位置、可前往节点与进入费用、守路与已知情报。
## 依据：技术方案第 9 节。

var _canvas: MapCanvas
var _detail: VBoxContainer
var _selected := ""


func build() -> void:
	var root := add_root("武道任务世界 · 大地图")
	root.add_child(UiKit.label(hud(), 15, UiKit.COL_TEXT))

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(holder)

	_canvas = MapCanvas.new()
	_canvas.state = ctrl.state
	_canvas.world_def = ctrl.world.world(ctrl.state)
	_canvas.world_service = ctrl.world
	_canvas.catalog = catalog
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(620, 420)
	_canvas.node_clicked.connect(_on_node_clicked)
	holder.add_child(_canvas)

	var right := UiKit.panel("节点信息")
	right.custom_minimum_size = Vector2(340, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	_detail = UiKit.vbox(6)
	rb.add_child(_detail)
	rb.add_child(UiKit.spacer(8))
	rb.add_child(UiKit.label("图例", 15, UiKit.COL_ACCENT))
	rb.add_child(UiKit.label("· 黄色圆环：当前所在节点", 13, UiKit.COL_ACCENT))
	rb.add_child(UiKit.label("· 绿色圆环：相邻可前往（上方数字为进入费用）", 13, UiKit.COL_MERCHANT))
	rb.add_child(UiKit.label("· 红色连线：被守路者封锁，需先击败守路者", 13, UiKit.COL_ENEMY))
	rb.add_child(UiKit.label("· 未探索节点只显示编号；已进入过显示名称", 13, UiKit.COL_MUTED))
	rb.add_child(UiKit.spacer(8))
	rb.add_child(UiKit.button("返回小地图", func() -> void: ctrl.close_world_map()))

	_refresh()


func _on_node_clicked(node_id: String) -> void:
	_selected = node_id
	_refresh()


func _refresh() -> void:
	if _detail == null:
		return
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	_detail.add_child(UiKit.label("当前位置：%s %s" % [
		ctrl.state.current_node_id, _node_name(ctrl.state.current_node_id),
	], 16, UiKit.COL_ACCENT))
	_detail.add_child(UiKit.label("货币 %d　下一新节点费用 %d" % [
		ctrl.state.money, ctrl.world.next_fee_preview(ctrl.state),
	], 14, UiKit.COL_TEXT))
	_detail.add_child(UiKit.spacer(6))
	if _selected == "":
		_detail.add_child(UiKit.label("点击地图上的节点查看详情。", 14, UiKit.COL_MUTED))
		return
	var nd := ctrl.world.world(ctrl.state).node_by_id(_selected)
	_detail.add_child(UiKit.label("选中节点：%s %s" % [_selected, _node_name(_selected)], 16, UiKit.COL_TEXT))
	if nd != null:
		_detail.add_child(UiKit.label("类型：%s" % MapLayout.area_name(_selected), 14, UiKit.COL_MUTED))
		var content := PackedStringArray()
		if not nd.shop_ids.is_empty():
			content.append("%d 家店铺" % nd.shop_ids.size())
		if not nd.enemies.is_empty():
			content.append("%d 个可选敌人" % nd.enemies.size())
		if not nd.npc_services.is_empty():
			content.append("%d 处人物" % nd.npc_services.size())
		if nd.has_container:
			content.append("容器")
		_detail.add_child(UiKit.label("已知内容：%s" % ("、".join(content) if content.size() > 0 else "无"), 14, UiKit.COL_TEXT))
	var discovered := ctrl.state.node_state(_selected).entered
	_detail.add_child(UiKit.label("是否进入过：%s" % ("是（重访免费）" if discovered else "否"), 14, UiKit.COL_MUTED))
	var fee := _canvas.fee_of(_selected)
	_detail.add_child(UiKit.label("本次进入费用：%s" % ("免费" if fee == 0 else "%d 货币" % fee), 15, UiKit.COL_ACCENT))
	var blocked := _is_blocked_to(_selected)
	if blocked:
		_detail.add_child(UiKit.label("该通路被守路者封锁，需先击败守路者。", 14, UiKit.COL_ENEMY))
	var can := ctrl.world.can_travel(ctrl.state, _selected)
	var check_ok := fee <= ctrl.state.money and not blocked
	var btn := UiKit.button("前往该节点", _on_travel, not (can.success and check_ok))
	_detail.add_child(btn)
	if not can.success:
		_detail.add_child(UiKit.label("不可前往：%s" % can.reason, 13, UiKit.COL_MUTED))
	elif not check_ok:
		_detail.add_child(UiKit.label("不可前往：费用不足或通路被封锁。", 13, UiKit.COL_MUTED))


func _node_name(node_id: String) -> String:
	var nd := ctrl.world.world(ctrl.state).node_by_id(node_id)
	return nd.display_name if nd != null else ""


func _is_blocked_to(node_id: String) -> bool:
	return ctrl.world.is_connection_blocked(ctrl.state, ctrl.state.current_node_id, node_id)


func _on_travel() -> void:
	if _selected == "":
		return
	ctrl.travel_to(_selected)
