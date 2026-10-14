class_name PageNodeCards
extends PageBase

var selected := ""
var board: GridContainer
var status: Label


func build() -> void:
	var root := add_root("节点 %s" % ctrl.state.current_node_id)
	status = UiKit.label("", 14, UiKit.COL_TEXT)
	root.add_child(status)
	var toolbar := UiKit.row(8)
	root.add_child(toolbar)
	toolbar.add_child(UiKit.pixel_art(HeroArt.pose(HeroArt.POSE_HOME), Vector2(32, 48)))
	toolbar.add_child(UiKit.button("大地图", ctrl.open_world_map))
	toolbar.add_child(UiKit.button("构筑与背包", func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP)))
	toolbar.add_child(UiKit.button("回归主神", ctrl.return_to_deity, not ctrl.state.main_completed))
	toolbar.add_child(UiKit.button("认输", ctrl.surrender))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	board = GridContainer.new()
	board.columns = 4
	board.add_theme_constant_override("h_separation", 12)
	board.add_theme_constant_override("v_separation", 12)
	scroll.add_child(board)
	_refresh()


func _refresh() -> void:
	var specs := ctrl.node_cards.specs(ctrl.state, catalog, ctrl.world, ctrl.encounters)
	var ns := ctrl.state.node_state(ctrl.state.current_node_id)
	ctrl.node_cards.initialize(ns, specs)
	for spec in specs:
		var id := "%s:%s" % [spec["kind"], spec["key"]]
		if ns.scene_cards.has(id):
			ns.scene_cards[id] = spec.duplicate(true)
	for child in board.get_children():
		board.remove_child(child)
		child.queue_free()
	status.text = "%s　探索时间 %d　%s" % [hud(), ctrl.state.exploration_time, "" if selected == "" else "已选杂物或容器"]
	for i in ns.card_lanes.size():
		var lane: Array = ns.card_lanes[i]
		var group := UiKit.vbox(6)
		group.custom_minimum_size = Vector2(220, 150)
		board.add_child(group)
		if lane.is_empty():
			group.add_child(UiKit.button("空位", _move_to.bind(i), selected == ""))
			continue
		for depth in lane.size():
			var id: String = lane[depth]
			var card: Dictionary = ns.scene_cards[id]
			var top := depth == lane.size() - 1
			var button := UiKit.button(String(card["label"]), _activate.bind(id), not top or bool(card.get("done", false)))
			button.custom_minimum_size = Vector2(220, 46)
			group.add_child(button)
		var top_id: String = lane.back()
		if ns.scene_cards[top_id]["kind"] in ["cover", "container"]:
			group.add_child(UiKit.button("选择移动", _select.bind(top_id)))
			if selected != "":
				group.add_child(UiKit.button("放到这里", _move_to.bind(i)))
	if selected != "":
		board.add_child(UiKit.button("取消移动", _select.bind("")))


func _select(id: String) -> void:
	selected = id
	_refresh()


func _move_to(destination: int) -> void:
	var result := ctrl.node_cards.move(ctrl.state.node_state(ctrl.state.current_node_id), selected, destination)
	if result.success:
		selected = ""
	_refresh()
	if not result.success:
		status.text = result.reason


func _activate(id: String) -> void:
	var ns := ctrl.state.node_state(ctrl.state.current_node_id)
	if not ctrl.node_cards.accessible(ns, id):
		return
	var spec: Dictionary = ns.scene_cards[id]
	match spec["kind"]:
		"cover": _select(id)
		"shop": ctrl.open_shop(spec["key"], RunController.PAGE_MINIMAP)
		"npc":
			ctrl.talk_to(StringName(spec["key"]))
			_refresh()
		"container":
			var result := ctrl.open_container_here(spec["key"])
			_refresh()
			if not result.success: status.text = result.reason
		"enemy": ctrl.open_pre_battle(spec["key"])
