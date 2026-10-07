class_name PageMinimap
extends PageBase
## 小地图：角色自由移动（CharacterBody2D + move_and_slide）与交互点（Area2D）。
## 边界：页面只提交命令并刷新显示；费用、容量、胜负与奖励判定全部由服务层完成。
## 依据：游戏可玩原型技术方案.md 第 9 节；游戏一阶段原型需求.md。

const MOVE_SPEED := 200.0
const PLAYER_RADIUS := 11.0
const AREA_RADIUS := 30.0
const WALL_THICKNESS := 10.0
const INSET := 26.0

var _canvas: Control
var _world: Node2D
var _player: CharacterBody2D
var _walls: StaticBody2D
var _areas: Array[Area2D] = []
var _specs: Array[Dictionary] = []
var _nearby: Array[Area2D] = []
var _prompt: Label
var _hud_label: Label
var _actions_box: VBoxContainer
var _info_box: VBoxContainer
var _room_built := false
var _auto_guard := false


func build() -> void:
	var root := add_root("世界探索 · 小地图")
	_hud_label = UiKit.label(hud(), 15, UiKit.COL_TEXT)
	root.add_child(_hud_label)

	var cols := UiKit.row(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)

	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(520, 340)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_canvas)

	var right := UiKit.panel("")
	right.custom_minimum_size = Vector2(340, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rb := UiKit.body(right)
	_actions_box = UiKit.vbox(6)
	rb.add_child(_actions_box)
	_prompt = UiKit.label("", 14, UiKit.COL_ACCENT)
	rb.add_child(_prompt)
	rb.add_child(UiKit.spacer(6))
	_info_box = UiKit.vbox(4)
	rb.add_child(_info_box)

	_build_room()
	_refresh()


# ---------------------------------------------------------------------------
# 房间与交互点
# ---------------------------------------------------------------------------

func _build_room() -> void:
	var floor := ColorRect.new()
	floor.name = "Floor"
	floor.color = Color(0.13, 0.14, 0.16)
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(floor)

	_world = Node2D.new()
	_world.name = "World"
	_canvas.add_child(_world)

	_walls = StaticBody2D.new()
	_world.add_child(_walls)

	_player = CharacterBody2D.new()
	_player.name = "Player"
	var pc := CollisionShape2D.new()
	var pshape := CircleShape2D.new()
	pshape.radius = PLAYER_RADIUS
	pc.shape = pshape
	_player.add_child(pc)
	var pvis := Polygon2D.new()
	pvis.polygon = _circle_points(PLAYER_RADIUS + 1.0)
	pvis.color = UiKit.COL_PLAYER
	_player.add_child(pvis)
	var plabel := Label.new()
	plabel.text = "玩家"
	plabel.add_theme_font_size_override("font_size", 12)
	plabel.add_theme_color_override("font_color", UiKit.COL_PLAYER)
	plabel.position = Vector2(-20, -26)
	plabel.custom_minimum_size = Vector2(60, 0)
	plabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player.add_child(plabel)
	_world.add_child(_player)

	_rebuild_interactables()
	_canvas.resized.connect(_on_canvas_resized)
	_room_built = true
	_layout_room()


func _on_canvas_resized() -> void:
	if _room_built:
		_layout_room()


## 可交互内容清单（纯计算，便于无画面断言）
func interactable_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ctrl == null or ctrl.state == null:
		return out
	var state := ctrl.state
	var w := ctrl.world.world(state)
	if w == null:
		return out
	var nd := w.node_by_id(state.current_node_id)
	if nd == null:
		return out
	for sid in nd.shop_ids:
		var sdef := catalog.shop(sid)
		out.append({
			"kind": "shop", "key": "%s/%s" % [state.current_node_id, sid],
			"label": "商铺：%s" % (sdef.display_name if sdef != null else String(sid)),
		})
	for svc in nd.npc_services:
		out.append({"kind": "npc", "key": String(svc), "label": "人物：%s" % _npc_name(svc)})
	for ck in ctrl.world.container_keys(state, state.current_node_id):
		var opened := bool((state.node_state(state.current_node_id).containers.get(ck, {}) as Dictionary).get("opened", false))
		out.append({
			"kind": "container", "key": ck,
			"label": "容器：搜刮" if not opened else "容器：已搜刮",
			"done": opened,
		})
	for ek in ctrl.node_enemy_keys():
		var tpl := ctrl.world.enemy_template_from_key(ek)
		var edef := catalog.enemy(tpl)
		var es := ctrl.encounters.ensure(state, state.current_node_id, ek)
		var tag := ""
		if es.defeated:
			tag = "（已击败）"
		elif es.is_guard:
			tag = "（守路者）"
		out.append({
			"kind": "enemy", "key": ek,
			"label": "战斗：%s%s" % [edef.display_name if edef != null else "敌人", tag],
			"done": es.defeated,
		})
	for nb in w.neighbors(state.current_node_id):
		var nnd := w.node_by_id(nb)
		var fee := ctrl.world.entry_fee(state, nb)
		var fee_txt := "免费" if fee == 0 else "%d 货币" % fee
		out.append({
			"kind": "exit", "key": nb,
			"label": "前往 %s %s（%s）" % [nb, nnd.display_name if nnd != null else "", fee_txt],
		})
	return out


func _npc_name(service: StringName) -> String:
	match service:
		NodeDef.NPC_SHOP:
			return "商人"
		NodeDef.NPC_INTEL_AREA:
			return "路人（打听土匪区域）"
		NodeDef.NPC_INTEL_TARGET:
			return "驿卒（打听头子位置）"
		NodeDef.NPC_QUEST_CHALLENGE:
			return "武师（挑战比试）"
		NodeDef.NPC_QUEST_SIDE:
			return "委托人（击杀路匪）"
	return String(service)


func _rebuild_interactables() -> void:
	for a in _areas:
		if is_instance_valid(a):
			a.queue_free()
	_areas.clear()
	_specs = interactable_specs()
	for spec in _specs:
		_areas.append(_make_area(spec))


func _make_area(spec: Dictionary) -> Area2D:
	var area := Area2D.new()
	area.name = "Area_%s" % spec.get("key", "")
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = AREA_RADIUS
	shape.shape = cs
	area.add_child(shape)
	var vis := Polygon2D.new()
	vis.polygon = _circle_points(15.0)
	vis.color = _kind_color(spec)
	area.add_child(vis)
	var label := Label.new()
	label.text = _short_label(spec)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _kind_color(spec))
	label.position = Vector2(-46, 16)
	label.custom_minimum_size = Vector2(92, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area.add_child(label)
	area.set_meta("spec", spec)
	area.body_entered.connect(_on_body_entered.bind(area))
	area.body_exited.connect(_on_body_exited.bind(area))
	_world.add_child(area)
	return area


func _kind_color(spec: Dictionary) -> Color:
	if bool(spec.get("done", false)):
		return Color(0.42, 0.42, 0.46)
	match String(spec.get("kind", "")):
		"enemy":
			return UiKit.COL_ENEMY
		"shop":
			return UiKit.COL_MERCHANT
		"npc":
			return UiKit.COL_INTEL
		"container":
			return UiKit.COL_ACCENT
		_:
			return UiKit.COL_MUTED


func _short_label(spec: Dictionary) -> String:
	match String(spec.get("kind", "")):
		"exit":
			return "通路 %s" % spec.get("key", "")
		"shop":
			return "商铺"
		"npc":
			return "人物"
		"container":
			return "容器"
		"enemy":
			return "敌人"
	return ""


func _layout_room() -> void:
	var w := maxf(_canvas.size.x, 320.0)
	var h := maxf(_canvas.size.y, 240.0)
	_player.position = Vector2(w * 0.5, h * 0.84)
	_player.velocity = Vector2.ZERO

	var n := _areas.size()
	for i in n:
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var angle := lerpf(-PI * 0.86, -PI * 0.14, t)
		var radius := Vector2(w * 0.36, h * 0.30)
		var pos := Vector2(w * 0.5, h * 0.44) + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		_areas[i].position = Vector2(clampf(pos.x, 60.0, w - 60.0), clampf(pos.y, 60.0, h - 70.0))

	_rebuild_walls(w, h)


func _rebuild_walls(w: float, h: float) -> void:
	for child in _walls.get_children():
		_walls.remove_child(child)
		child.queue_free()
	var half_t := WALL_THICKNESS * 0.5
	var specs := [
		{"size": Vector2(w, WALL_THICKNESS), "pos": Vector2(w * 0.5, INSET - half_t)},
		{"size": Vector2(w, WALL_THICKNESS), "pos": Vector2(w * 0.5, h - INSET + half_t)},
		{"size": Vector2(WALL_THICKNESS, h), "pos": Vector2(INSET - half_t, h * 0.5)},
		{"size": Vector2(WALL_THICKNESS, h), "pos": Vector2(w - INSET + half_t, h * 0.5)},
	]
	for s in specs:
		var body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = s["size"]
		cs.shape = rect
		body.position = s["pos"]
		body.add_child(cs)
		_walls.add_child(body)


static func _circle_points(radius: float, segments: int = 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


# ---------------------------------------------------------------------------
# 移动与接触
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _player == null or not _room_built:
		return
	var dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	if dir.length() > 1.0:
		dir = dir.normalized()
	_player.velocity = dir * MOVE_SPEED
	_player.move_and_slide()
	_update_prompt()


func _on_body_entered(body: Node2D, area: Area2D) -> void:
	if body != _player:
		return
	if not _nearby.has(area):
		_nearby.append(area)
	_update_prompt()
	var spec: Dictionary = area.get_meta("spec", {})
	if String(spec.get("kind", "")) == "enemy" and not bool(spec.get("done", false)):
		_maybe_auto_open(String(spec.get("key", "")))


func _on_body_exited(body: Node2D, area: Area2D) -> void:
	if body != _player:
		return
	_nearby.erase(area)
	_update_prompt()
	var spec: Dictionary = area.get_meta("spec", {})
	if String(spec.get("kind", "")) == "enemy":
		# 离开接触范围后解除该敌人的自动弹窗屏蔽
		ctrl.set_suppression(String(spec.get("key", "")), false)


## 敌人接触自动打开战前界面；取消过后先屏蔽，离开接触区域再解除
func _maybe_auto_open(encounter_key: String) -> void:
	if _auto_guard:
		return
	var es := ctrl.encounters.ensure(ctrl.state, ctrl.state.current_node_id, encounter_key)
	if es.auto_prompt_suppressed or es.defeated:
		return
	_auto_guard = true
	call_deferred("_open_pre_battle", encounter_key)


func _open_pre_battle(encounter_key: String) -> void:
	_auto_guard = false
	if not is_inside_tree():
		return
	ctrl.open_pre_battle(encounter_key)


func _nearest() -> Area2D:
	var best: Area2D = null
	var best_d := INF
	for a in _nearby:
		if not is_instance_valid(a):
			continue
		var d := _player.global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


func _update_prompt() -> void:
	if _prompt == null or _player == null:
		return
	var a := _nearest()
	if a == null:
		_prompt.text = "靠近交互点后按 E 交互（也可直接点击右侧按钮）"
		return
	var spec: Dictionary = a.get_meta("spec", {})
	if bool(spec.get("done", false)) and String(spec.get("kind", "")) == "enemy":
		_prompt.text = "E：该敌人已击败"
	else:
		_prompt.text = "E：%s" % spec.get("label", "")


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if event.is_action_pressed("interact"):
		var a := _nearest()
		if a == null:
			return
		var spec: Dictionary = a.get_meta("spec", {})
		_activate(spec)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_world_map"):
		ctrl.open_world_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_build"):
		ctrl.open_build(RunController.PAGE_MINIMAP)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 命令转发
# ---------------------------------------------------------------------------

func _activate(spec: Dictionary) -> void:
	match String(spec.get("kind", "")):
		"shop":
			ctrl.open_shop(String(spec.get("key", "")), RunController.PAGE_MINIMAP)
		"npc":
			ctrl.talk_to(StringName(spec.get("key", "")))
			_refresh()
		"container":
			if bool(spec.get("done", false)):
				if _prompt != null:
					_prompt.text = "这个容器已经搜刮过了"
			else:
				ctrl.open_container_here(String(spec.get("key", "")))
				_refresh()
				_rebuild_interactables()
				_layout_room()
		"enemy":
			if bool(spec.get("done", false)):
				if _prompt != null:
					_prompt.text = "该敌人已被击败"
			else:
				ctrl.open_pre_battle(String(spec.get("key", "")))
		"exit":
			var r := ctrl.travel_to(String(spec.get("key", "")))
			if r.success:
				return
			_refresh()


func _surrender() -> void:
	ctrl.surrender()


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _hud_label != null:
		_hud_label.text = hud()
	_fill_actions()
	_fill_info()
	_update_prompt()


func _fill_actions() -> void:
	if _actions_box == null:
		return
	for c in _actions_box.get_children():
		_actions_box.remove_child(c)
		c.queue_free()
	_actions_box.add_child(UiKit.label("当前节点可交互", 16, UiKit.COL_ACCENT))
	if _specs.is_empty():
		_specs = interactable_specs()
	for spec in _specs:
		var disabled := bool(spec.get("done", false)) and String(spec.get("kind", "")) == "enemy"
		var b := UiKit.button(String(spec.get("label", "")), _activate.bind(spec), disabled)
		_actions_box.add_child(b)
	_actions_box.add_child(UiKit.spacer(8))
	_actions_box.add_child(UiKit.button("打开大地图（Tab）", func() -> void: ctrl.open_world_map()))
	_actions_box.add_child(UiKit.button("构筑与整理（B）", func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP)))
	var can_ret := ctrl.world.can_return(ctrl.state)
	var ret_btn := UiKit.button("回归主神空间", _on_return, not can_ret.success)
	_actions_box.add_child(ret_btn)
	if not can_ret.success:
		_actions_box.add_child(UiKit.label("回归不可用：%s" % can_ret.reason, 13, UiKit.COL_MUTED))
	_actions_box.add_child(UiKit.spacer(8))
	_actions_box.add_child(UiKit.button("主动认输", _surrender))


func _on_return() -> void:
	ctrl.return_to_deity()


func _fill_info() -> void:
	if _info_box == null:
		return
	for c in _info_box.get_children():
		_info_box.remove_child(c)
		c.queue_free()
	var state := ctrl.state
	_info_box.add_child(UiKit.label("任务与情报", 16, UiKit.COL_ACCENT))
	var w := ctrl.world.world(state)
	if w == null:
		return
	for qdef in w.quests:
		var qs := state.quest_state(qdef.quest_id)
		var status := "未接取"
		match qs.status:
			QuestState.STATUS_ACCEPTED:
				status = "进行中"
			QuestState.STATUS_COMPLETED:
				status = "待领奖"
			QuestState.STATUS_CLAIMED:
				status = "已完成"
		var mark := "主线" if qdef.is_main else "支线"
		_info_box.add_child(UiKit.label("[%s] %s：%s" % [mark, qdef.display_name, status], 14, UiKit.COL_TEXT))
		_info_box.add_child(UiKit.label("　%s" % qdef.description, 13, UiKit.COL_MUTED))
	var intel := PackedStringArray()
	if state.known_intel.has("bandit_area"):
		intel.append("土匪活动区域已得知")
	if state.known_intel.has("chief_node"):
		intel.append("头子位置：15 号主寨（重锤，高伤害、长冷却）")
	_info_box.add_child(UiKit.label("情报：%s" % ("、".join(intel) if intel.size() > 0 else "暂无"), 14, UiKit.COL_MUTED))
	_info_box.add_child(UiKit.label("下一新节点进入费用：%d 货币" % ctrl.world.next_fee_preview(state), 14, UiKit.COL_MUTED))
	_info_box.add_child(UiKit.label("战术提示：中毒绕过护盾；沙尘暴第 30 秒开始，忽略护盾与减伤。", 13, UiKit.COL_MUTED))
