class_name PageMinimap
extends PageBase
## 世界场景：角色自由移动（CharacterBody2D + move_and_slide）与交互点（Area2D）。
## 顶部状态栏（生命/金币/剩余机会/十格战斗栏/技能栏）+ 底部背包贴底 + 右上小地图框
## 均为系统组件叠加层，矩形取自 SystemSkin，本页不写死坐标。
##
## 边界：页面只提交命令并刷新显示；费用、容量、胜负与奖励判定全部由服务层完成。
## 依据：游戏主界面与交互调整方案.md §1, §2, §6；技术方案第 9 节。

const MOVE_SPEED := 200.0
const PLAYER_RADIUS := 11.0
const AREA_RADIUS := 30.0
const WALL_THICKNESS := 10.0
const INSET := 26.0
## 主角立绘缩放：素材约 106×186，缩到 0.45 后高约 84，与 340 高的房间相称。
const HERO_SCALE := 0.45

## 世界画布高度：底部 inventory_tray 上沿以上。设计画布 690 减去 inventory_tray
## 高 153 与下边距 8 = 529。世界画布只占这一段高度，避免角色走到叠加层下面。
const WORLD_H := 529

var _design_canvas: Control
var _canvas: Control
var _world: Node2D
var _player: CharacterBody2D
var _hero: Sprite2D
var _hero_dir: StringName = HeroArt.DIR_UP
var _hero_phase := 0.0
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

## HUD 叠加层组件（系统组件 v1）
var _mm_preview: Control           ## 小地图框内的小型预览
var _status_panel_node: NinePatchRect
var _inventory_tray_node: NinePatchRect
var _bb_field: Control              ## 状态栏战斗栏格线
var _bb_cells: Array = []            ## 状态栏战斗栏物品格
var _inv_field: Control             ## 背包栏格线
var _inv_cells: Array = []           ## 背包栏物品格
var _skill_holder: Control         ## 技能栏滚动容器
var _skill_items: Array = []         ## 已创建的技能图标引用
var _toast_label: Label             ## 短提示
var _tooltip_layer: Control         ## 共用悬浮说明（tooltip_panel）
var _tooltip_title: Label
var _tooltip_body: Label
var _menu_layer: Control            ## 背包物品右键菜单（context_menu）
var _menu_instance_id := ""         ## 当前菜单指向的物品实例
var _hp_label: Label
var _stats_label: Label
var _gold_label: Label

## 拖拽状态机（物品拖拽重排/装备/卸下，依据 主界面方案 §7）。
var _drag_item: ItemInstance = null        ## 正在拖拽的物品实例
var _drag_src := ""                        ## 来源栏 "bar"/"inv"
var _drag_cell: Button = null              ## 原物品格（用于淡影）
var _drag_preview: Control = null          ## 跟随鼠标的半透明预览
var _drag_offset := Vector2.ZERO           ## 抓取点相对物品格的偏移
var _drop_field: Control = null            ## 当前悬停的目标栏控件
var _drop_index := -1                      ## 当前悬停的目标格位
var _drop_valid := false                   ## 当前落点是否合法
var _drop_reason := ""                     ## 非法原因
var _drop_ghost: Control = null            ## 落点预览覆盖层（合法浅蓝/非法红）
var _cell_map: Dictionary = {}             ## instance_id -> {cell, field, where}
var _skill_offset := 0.0                   ## 技能栏横向滚动偏移
var _skill_arrows: Control = null          ## 技能溢出箭头层
var _skill_left_arrow: Button = null
var _skill_right_arrow: Button = null


func build() -> void:
	# CenterContainer + 设计画布（1280×690），与战斗页、共用面板保持一致。
	# 容器会把子节点按最小尺寸排，所以设计画布的尺寸就是页面真实尺寸。
	var center := CenterContainer.new()
	center.name = "WorldCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_design_canvas = Control.new()
	_design_canvas.name = "DesignCanvas"
	var design := SystemSkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_design_canvas.custom_minimum_size = Vector2(design)
	center.add_child(_design_canvas)
	_design_canvas.add_child(UiKit.solid(UiKit.COL_BG, Rect2i(Vector2i.ZERO, design)))

	# 世界画布在上半区，玩家移动范围限制在 inventory_tray 上沿以上。
	_canvas = Control.new()
	_canvas.name = "WorldCanvas"
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(design.x, WORLD_H)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_canvas)

	_build_room()
	_build_overlays()
	_refresh()


## 叠加层：小地图框、状态栏、背包、操作面板（系统组件 v1，矩形取自 SystemSkin）。
func _build_overlays() -> void:
	# 顶部 HUD 文字（开发用，可隐藏）
	_hud_label = UiKit.abs_sys_label(hud(), 13,
		Rect2i(12, 4, 700, 18), UiKit.COL_SYS_TEXT)
	_hud_label.name = "WorldHud"
	_design_canvas.add_child(_hud_label)

	# 右上角小地图框（装饰边框，内部为空白透明）。
	var mm_frame := UiKit.abs_sys_panel(SystemSkin.MINIMAP_FRAME, 0.6)
	if mm_frame != null:
		_design_canvas.add_child(mm_frame)
	# 框内的小型预览：当前节点 + 相邻节点 + 玩家位置，简化绘制。
	_mm_preview = Control.new()
	_mm_preview.name = "MinimapPreview"
	var mm_rect := SystemSkin.rect(SystemSkin.MINIMAP_FRAME)
	var map_view := SystemSkin.region_abs(SystemSkin.MINIMAP_FRAME, "map_view")
	_mm_preview.position = Vector2(map_view.position)
	_mm_preview.size = Vector2(map_view.size)
	_mm_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mm_preview.draw.connect(_on_mm_draw)
	_design_canvas.add_child(_mm_preview)

	# 状态栏（背包上方）：HP/金币/剩余机会 + 十格战斗栏 + 技能栏
	_status_panel_node = UiKit.abs_sys_panel(SystemSkin.STATUS_PANEL, 0.55)
	if _status_panel_node != null:
		_design_canvas.add_child(_status_panel_node)
	_build_status_content()

	# 底部背包贴底
	_inventory_tray_node = UiKit.abs_sys_panel(SystemSkin.INVENTORY_TRAY, 0.55)
	if _inventory_tray_node != null:
		_design_canvas.add_child(_inventory_tray_node)
	_build_inventory_content()

	# 右上动作列表（开发用，可隐藏）——放在小地图框下方
	var actions_holder := PanelContainer.new()
	actions_holder.name = "DevActions"
	actions_holder.position = Vector2(mm_rect.position.x, mm_rect.position.y + mm_rect.size.y + 6)
	actions_holder.size = Vector2(mm_rect.size.x, 220)
	actions_holder.self_modulate.a = 0.7
	_design_canvas.add_child(actions_holder)
	var rb := VBoxContainer.new()
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_holder.add_child(rb)
	_actions_box = UiKit.vbox(4)
	rb.add_child(_actions_box)
	_prompt = UiKit.label("", 12, UiKit.COL_ACCENT)
	rb.add_child(_prompt)
	rb.add_child(UiKit.spacer(4))
	_info_box = UiKit.vbox(4)
	rb.add_child(_info_box)

	_build_tooltip_layer()
	_build_context_menu_layer()


## 共用悬浮说明（tooltip_panel）：悬停物品/技能时显示，随鼠标位置浮动。
func _build_tooltip_layer() -> void:
	_tooltip_layer = UiKit.abs_sys_panel(SystemSkin.TOOLTIP_PANEL, 0.95)
	if _tooltip_layer == null:
		return
	_tooltip_layer.name = "ItemTooltip"
	_tooltip_layer.visible = false
	_tooltip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_tooltip_layer)
	var content := SystemSkin.region(SystemSkin.TOOLTIP_PANEL, "content")
	_tooltip_title = UiKit.abs_sys_label("", 14,
		Rect2i(content.position, Vector2i(content.size.x, 22)), UiKit.COL_SYS_TEXT)
	_tooltip_body = UiKit.abs_sys_label("", 12,
		Rect2i(content.position.x, content.position.y + 26, content.size.x, content.size.y - 30),
		UiKit.COL_SYS_MUTED)
	_tooltip_layer.add_child(_tooltip_title)
	_tooltip_layer.add_child(_tooltip_body)


func _show_tooltip(title: String, body: String, at: Vector2) -> void:
	if _tooltip_layer == null:
		return
	_tooltip_title.text = title
	_tooltip_body.text = body
	var size := _tooltip_layer.size
	# 贴着指针右下方显示，越界时向内收
	var pos := at + Vector2(14, 10)
	pos.x = minf(pos.x, _design_canvas.size.x - size.x - 4.0)
	pos.y = minf(pos.y, _design_canvas.size.y - size.y - 4.0)
	_tooltip_layer.position = pos
	_tooltip_layer.visible = true


func _hide_tooltip() -> void:
	if _tooltip_layer != null:
		_tooltip_layer.visible = false


## 背包物品右键菜单（context_menu）：使用／丢弃两项，操作结果走短提示。
func _build_context_menu_layer() -> void:
	_menu_layer = UiKit.abs_sys_panel(SystemSkin.CONTEXT_MENU, 1.0)
	if _menu_layer == null:
		return
	_menu_layer.name = "ContextMenu"
	_menu_layer.visible = false
	_design_canvas.add_child(_menu_layer)


func _show_context_menu(instance_id: String, at: Vector2) -> void:
	if _menu_layer == null:
		return
	for c in _menu_layer.get_children():
		_menu_layer.remove_child(c)
		c.queue_free()
	_menu_instance_id = instance_id
	var items_r := SystemSkin.region(SystemSkin.CONTEXT_MENU, "items")
	var row_h := items_r.size.y / 2
	_menu_layer.add_child(UiKit.abs_button("使用", _on_menu_use,
		Rect2i(items_r.position, Vector2i(items_r.size.x, row_h - 2)), 12))
	_menu_layer.add_child(UiKit.abs_button("丢弃", _on_menu_discard,
		Rect2i(items_r.position.x, items_r.position.y + row_h + 2, items_r.size.x, row_h - 2), 12))
	var size := _menu_layer.size
	var pos := at + Vector2(8, 6)
	pos.x = minf(pos.x, _design_canvas.size.x - size.x - 4.0)
	pos.y = minf(pos.y, _design_canvas.size.y - size.y - 4.0)
	_menu_layer.position = pos
	_menu_layer.visible = true


func _hide_context_menu() -> void:
	if _menu_layer != null:
		_menu_layer.visible = false
	_menu_instance_id = ""


func _on_menu_use() -> void:
	var id := _menu_instance_id
	_hide_context_menu()
	var res := ctrl.use_recovery(id)
	if res.success:
		_toast("已使用")
	else:
		_toast(res.reason)


func _on_menu_discard() -> void:
	var id := _menu_instance_id
	_hide_context_menu()
	var res := ctrl.discard_item(id)
	if res.success:
		_toast("已丢弃")
	else:
		_toast(res.reason)

	# 短提示（操作失败/取消时显示，2 秒消失）
	_toast_label = UiKit.abs_sys_label("", 13,
		Rect2i(64, 326, 1152, 22), UiKit.COL_SYS_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.name = "Toast"
	_toast_label.visible = false
	_design_canvas.add_child(_toast_label)


## 状态栏内容：左侧数值、中间十格战斗栏、右侧技能栏
func _build_status_content() -> void:
	# 左侧 stats 区
	var stats_rect := SystemSkin.region_abs(SystemSkin.STATUS_PANEL, "stats")
	_hp_label = UiKit.abs_sys_label("", 14,
		Rect2i(stats_rect.position.x + 6, stats_rect.position.y + 4,
			stats_rect.size.x, 24), UiKit.COL_SYS_TEXT)
	_hp_label.name = "StatsHp"
	_design_canvas.add_child(_hp_label)
	_stats_label = UiKit.abs_sys_label("", 12,
		Rect2i(stats_rect.position.x + 6, stats_rect.position.y + 30,
			stats_rect.size.x, 18), UiKit.COL_SYS_TEXT)
	_stats_label.name = "StatsMain"
	_design_canvas.add_child(_stats_label)
	_gold_label = UiKit.abs_sys_label("", 12,
		Rect2i(stats_rect.position.x + 6, stats_rect.position.y + 50,
			stats_rect.size.x, 18), UiKit.COL_SYS_MUTED)
	_gold_label.name = "StatsGold"
	_design_canvas.add_child(_gold_label)

	# 中间十格战斗栏：格宽 = 净宽 ÷ 10
	var bb_rect := SystemSkin.region_abs(SystemSkin.STATUS_PANEL, "battle_bar")
	_bb_field = SlotField.new()
	_bb_field.name = "StatusBarField"
	_bb_field.slot_count = 10
	_bb_field.position = Vector2(bb_rect.position)
	_bb_field.size = Vector2(bb_rect.size)
	_bb_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_bb_field)

	# 右侧技能栏：单行圆形图标，溢出时支持悬停滚轮横向浏览（实际滚动后续接入）
	var sk_rect := SystemSkin.region_abs(SystemSkin.STATUS_PANEL, "skills")
	_skill_holder = Control.new()
	_skill_holder.name = "SkillHolder"
	_skill_holder.position = Vector2(sk_rect.position)
	_skill_holder.size = Vector2(sk_rect.size)
	_skill_holder.clip_contents = true
	_skill_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_skill_holder.gui_input.connect(_on_skill_wheel)
	_design_canvas.add_child(_skill_holder)


## 底部背包内容：十格物品栏
func _build_inventory_content() -> void:
	var slots_rect := SystemSkin.region_abs(SystemSkin.INVENTORY_TRAY, "slots")
	_inv_field = SlotField.new()
	_inv_field.name = "InventoryTrayField"
	_inv_field.slot_count = 10
	_inv_field.position = Vector2(slots_rect.position)
	_inv_field.size = Vector2(slots_rect.size)
	_inv_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design_canvas.add_child(_inv_field)


# ---------------------------------------------------------------------------
# 房间与交互点
# ---------------------------------------------------------------------------

func _build_room() -> void:
	var floor := ColorRect.new()
	floor.name = "Floor"
	floor.color = Color(0.13, 0.14, 0.16)
	floor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	# 主角形象：四方向行走序列。左向的素材由管线水平镜像生成，
	# 运行时不需要再翻转，避免各页面各写一套翻转逻辑。
	_hero = Sprite2D.new()
	_hero.name = "HeroSprite"
	_hero.texture = HeroArt.walk(HeroArt.DIR_UP, 0)
	_hero.scale = Vector2(HERO_SCALE, HERO_SCALE)
	_hero.z_index = 1
	# 像素图必须最近邻采样，线性插值会糊边。
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var hero_size := HeroArt.size_of(_hero.texture)
	# 素材是底对齐的：把脚底对到碰撞圆位置，而不是把图片中心放过去，
	# 否则角色会「浮」在碰撞圆上方半个身位。
	_hero.offset = Vector2(0.0, PLAYER_RADIUS - hero_size.y * 0.5)
	_player.add_child(_hero)
	var plabel := Label.new()
	plabel.text = "玩家"
	plabel.add_theme_font_size_override("font_size", 12)
	plabel.add_theme_color_override("font_color", UiKit.COL_PLAYER)
	plabel.position = Vector2(-30, -(hero_size.y * HERO_SCALE) - 6.0)
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

func _physics_process(delta: float) -> void:
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
	_update_hero(dir, delta)
	_update_prompt()


## 指示物朝向与行走帧。静止时回到该方向的第 0 帧（站立），移动时按时间推进帧序号。
func _update_hero(dir: Vector2, delta: float) -> void:
	if _hero == null:
		return
	if dir == Vector2.ZERO:
		_hero_phase = 0.0
		_hero.texture = HeroArt.walk(_hero_dir, 0)
		return
	_hero_dir = HeroArt.direction_of(dir)
	_hero_phase += delta
	_hero.texture = HeroArt.walk(_hero_dir, HeroArt.frame_index(_hero_phase))


## 指示物当前状态（无画面验证与调试使用）
func hero_indicator() -> Dictionary:
	return {
		"node": _hero,
		"direction": _hero_dir,
		"frame": HeroArt.frame_index(_hero_phase),
		"texture": null if _hero == null else _hero.texture,
		"scale": HERO_SCALE,
		"collision_radius": PLAYER_RADIUS,
	}


## 按方向驱动指示物，供无画面验证直接调用（无画面模式下不派发帧循环）
func drive_hero(dir: Vector2, delta: float) -> void:
	_update_hero(dir, delta)


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
	# 页面已脱离界面或正在释放时不再响应输入。
	# 刻意不用 is_inside_tree()：无画面脚本模式下连 SceneTree.root 的该标志都是 false，
	# 用它会把键盘输入全部吞掉，导致按键路径无法自动验证。
	if get_parent() == null or is_queued_for_deletion():
		return
	# 拖拽中 Esc 优先取消拖动（不关闭面板，依据 §12 拖动取消规则）
	if event.is_action_pressed("cancel") and _drag_item != null:
		_finish_drag(false)
		consume_input()
		return
	if event.is_action_pressed("cancel"):
		# Esc 优先级链：右键菜单（最上层提示）→ 状态栏 → 无
		if _menu_layer != null and _menu_layer.visible:
			_hide_context_menu()
			consume_input()
			return
		if ctrl.status_bar_open():
			ctrl.toggle_status_bar()
			_update_overlay_visibility()
			consume_input()
			return
	if event.is_action_pressed("interact"):
		var a := _nearest()
		if a == null:
			_toast("附近无可交互对象")
			return
		var spec: Dictionary = a.get_meta("spec", {})
		_activate(spec)
		consume_input()
	elif event.is_action_pressed("cycle_target"):
		cycle_target()
		consume_input()
	elif event.is_action_pressed("toggle_status"):
		# Tab：切换状态栏（联动背包），不打开信息页（信息页用 M）
		ctrl.toggle_status_bar()
		_update_overlay_visibility()
		consume_input()
	elif event.is_action_pressed("open_world_map"):
		# M：信息页（世界节点、任务、目标、情报）
		ctrl.open_world_map()
		consume_input()
	elif event.is_action_pressed("open_build"):
		# B：独立切换背包显示（不打开模态整理页；整理页另有入口）
		ctrl.toggle_bag()
		_update_overlay_visibility()
		consume_input()


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
				var cr := ctrl.open_container_here(String(spec.get("key", "")))
				_refresh()
				_rebuild_interactables()
				_layout_room()
				_flash_landed(cr)
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


## 搜刮入包后的合成反馈（§11）：在最终落袋的背包格上短暂闪光。
## 产物 id 由 open_container_here 以 landed_ids 回传；背包隐藏时不闪（无落位可指）。
func _flash_landed(cr: OperationResult) -> void:
	if cr == null or not cr.success:
		return
	if not ctrl.bag_open():
		return
	var ids: Array = cr.data.get("landed_ids", [])
	for iid in ids:
		var info: Dictionary = _cell_map.get(String(iid), {})
		var cell: Control = info.get("cell", null)
		if cell != null and is_instance_valid(cell):
			UiKit.flash_control(cell)


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
	_refresh_overlays()


## 刷新系统组件叠加层：状态栏数值/战斗栏/技能栏/背包/小地图预览。
func _refresh_overlays() -> void:
	if ctrl == null or ctrl.state == null:
		return
	var state := ctrl.state
	if _hp_label != null:
		_hp_label.text = "生命 %d/%d" % [int(state.current_hp), int(state.max_hp)]
	if _stats_label != null:
		_stats_label.text = "剩余机会 %d/%d" % [RunState.MAX_DEFEATS - state.defeats, RunState.MAX_DEFEATS]
	if _gold_label != null:
		_gold_label.text = "货币 %d" % state.money
	_cell_map.clear()
	_layout_field(state.battle_bar, _bb_field, RunState.BAR_CAPACITY)
	_layout_inventory_tray(state.inventory)
	_layout_skills(state.skills)
	if _mm_preview != null:
		_mm_preview.queue_redraw()
	_update_overlay_visibility()


## 按 Tab/B 开关状态控制状态栏与背包的显隐。
## Tab 联动：状态栏开→背包也显示；状态栏关→恢复此前背包开关状态。
## 只改显示，不复制物品、不重新生成背包，不停止移动。
func _update_overlay_visibility() -> void:
	if ctrl == null:
		return
	var show_status := ctrl.status_bar_open()
	var show_bag := ctrl.bag_open()
	_set_status_visible(show_status)
	_set_bag_visible(show_bag)


func _set_status_visible(visible: bool) -> void:
	if _status_panel_node != null:
		_status_panel_node.visible = visible
	for n in [_hp_label, _stats_label, _gold_label, _bb_field, _skill_holder]:
		if n != null:
			n.visible = visible
	if _skill_left_arrow != null:
		_skill_left_arrow.visible = visible and _skill_overflowing()
	if _skill_right_arrow != null:
		_skill_right_arrow.visible = visible and _skill_overflowing()


func _set_bag_visible(visible: bool) -> void:
	if _inventory_tray_node != null:
		_inventory_tray_node.visible = visible
	if _inv_field != null:
		_inv_field.visible = visible


## 技能是否溢出（用于箭头显隐）。
func _skill_overflowing() -> bool:
	if _skill_holder == null or _skill_items.is_empty():
		return false
	var last: Control = _skill_items[-1]["node"]
	var content_w := last.position.x + last.size.x + 2.0
	return content_w > _skill_holder.size.x + 1.0


## 小地图预览绘制：把世界坐标等比缩进框内内腔，画交互点与玩家位置。
## 世界画布尺寸取 _canvas 实际大小；预览取框的 map_view 内腔。
func _on_mm_draw() -> void:
	if _canvas == null or _mm_preview == null:
		return
	var world := _canvas.size
	var view := _mm_preview.size
	if world.x <= 0.0 or world.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return
	var scale := minf(view.x / world.x, view.y / world.y)
	var offset := (view - world * scale) * 0.5
	# 交互点：按 kind 取色（与场景内圆点一致）
	for a in _areas:
		var spec: Dictionary = a.get_meta("spec", {})
		var col := _kind_color(spec)
		var p := offset + a.position * scale
		_mm_preview.draw_circle(p, 3.0, col)
	# 玩家：亮色小点 + 细描边，保证在深色内腔上可辨
	if _player != null:
		var pp := offset + _player.position * scale
		_mm_preview.draw_circle(pp, 3.5, UiKit.COL_PLAYER)
		_mm_preview.draw_arc(pp, 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.55), 1.0)


## 在指定格线控件中按占格摆放物品框（战斗栏）。
func _layout_field(items: Array, field: Control, capacity: int) -> void:
	if field == null:
		return
	for c in field.get_children():
		field.remove_child(c)
		c.queue_free()
	if items.is_empty():
		field.queue_redraw()
		return
	var n := maxi(capacity, 1)
	var slot_w := field.size.x / float(n)
	var cursor := 0
	for it in items:
		var def := catalog.item(it.definition_id)
		var span := maxi(def.size if def != null else 1, 1)
		if cursor + span > n:
			break
		var lo := roundf(cursor * slot_w)
		var hi := roundf((cursor + span) * slot_w)
		var box := Rect2(lo, 0, maxf(hi - lo, 1.0), field.size.y)
		_make_cell(it, box, field, "bar")
		cursor += span
	field.queue_redraw()


## 底部背包栏：占格累加，物品框按格宽计算。
func _layout_inventory_tray(items: Array) -> void:
	if _inv_field == null:
		return
	for c in _inv_field.get_children():
		_inv_field.remove_child(c)
		_inv_field.queue_free()
	if items.is_empty():
		_inv_field.queue_redraw()
		return
	var n := RunState.INVENTORY_CAPACITY
	var slot_w := _inv_field.size.x / float(n)
	var cursor := 0
	for it in items:
		var def := catalog.item(it.definition_id)
		var span := maxi(def.size if def != null else 1, 1)
		if cursor + span > n:
			break
		var lo := roundf(cursor * slot_w)
		var hi := roundf((cursor + span) * slot_w)
		var box := Rect2(lo, 0, maxf(hi - lo, 1.0), _inv_field.size.y)
		_make_cell(it, box, _inv_field, "inv")
		cursor += span
	_inv_field.queue_redraw()


## 单个物品格：品质色方形边框 + 物品名 + 品质·格数小字。
## 可交互（悬浮说明 / 右键菜单 / 拖拽起手），mouse_filter 在拖拽时临时忽略以透传到落点栏。
func _make_cell(it: ItemInstance, box: Rect2, field: Control, where: String) -> void:
	var cell := ItemCard.new()
	cell.name = "Cell_%s" % it.instance_id
	cell.position = box.position
	cell.size = box.size
	cell.focus_mode = Control.FOCUS_NONE
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.configure({"definition": catalog.item(it.definition_id), "instance": it, "quality": it.quality})
	field.add_child(cell)


	cell.mouse_exited.connect(_on_cell_unhover)
	cell.gui_input.connect(_on_cell_gui.bind(cell, it, where))
	_cell_map[it.instance_id] = {"cell": cell, "field": field, "where": where}


# ---------------------------------------------------------------------------
# 物品格交互：悬浮说明、右键菜单、拖拽
# ---------------------------------------------------------------------------

func _on_cell_hover(cell: Control, it: ItemInstance) -> void:
	if _drag_item != null:
		return
	_show_item_tooltip(it, cell)


func _on_cell_unhover() -> void:
	_hide_tooltip()


## 物品悬浮说明：名称、品质、占格、冷却、效果、被动。
func _show_item_tooltip(it: ItemInstance, at_node: Control) -> void:
	var def := catalog.item(it.definition_id)
	if def == null:
		return
	var lines := PackedStringArray()
	lines.append("%s（%s）" % [def.display_name, PriceTable.quality_name(it.quality)])
	lines.append("占格 %d　冷却 %.1f 秒" % [def.size, float(def.cooldown_ms) / 1000.0])
	var eff := UiKit.effect_text(def)
	if eff != "":
		lines.append(eff)
	var trig := UiKit.trigger_text(def)
	if trig != "":
		lines.append(trig)
	if it.trial_growth != 0.0:
		lines.append("试炼成长 +%.0f" % it.trial_growth)
	lines.append("右键打开操作菜单")
	_show_tooltip("%s" % def.display_name, "\n".join(lines), _design_canvas.get_local_mouse_position())


## 技能悬浮说明：名称、品质、触发条件、效果，自动生效、不占物品格。
func _on_skill_hover(skill_id: StringName, ss: SkillState) -> void:
	if _drag_item != null:
		return
	var sd := catalog.skill(skill_id)
	if sd == null:
		return
	var lines := PackedStringArray()
	lines.append("%s（%s）" % [sd.display_name, PriceTable.quality_name(ss.quality)])
	lines.append("触发「%s」→ %s %.1f" % [sd.trigger_event, sd.effect_type, sd.value_at(ss.quality)])
	lines.append("自动生效，不占物品格")
	if sd.description != "":
		lines.append(sd.description)
	_show_tooltip("%s" % sd.display_name, "\n".join(lines), _design_canvas.get_local_mouse_position())


func _on_skill_unhover() -> void:
	_hide_tooltip()


## 物品格输入：右键菜单、左键拖拽起手/移动/释放。
## 拖拽期间鼠标释放事件仍会路由回按下时的这个 cell（Godot 按钮捕获），
## 所以移动与释放都在这一个入口处理，不另设全屏捕获层。
func _on_cell_gui(event: InputEvent, cell: Button, it: ItemInstance, where: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_open_item_menu(it, cell)
			cell.accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_begin_drag(it, where, cell)
			cell.accept_event()
			return
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _drag_item == it:
			_finish_drag(true)
			cell.accept_event()
			return
	elif event is InputEventMouseMotion and _drag_item == it:
		_update_drag_preview()
		cell.accept_event()
		return


## 打开物品右键菜单：只显示该物品适用的操作（恢复品可用，持有物品可丢弃）。
func _open_item_menu(it: ItemInstance, cell: Button) -> void:
	var def := catalog.item(it.definition_id)
	var can_use := def != null and def.category == ItemDef.CAT_CONSUMABLE \
		and ctrl.state.current_hp < ctrl.state.max_hp and it.location != ItemInstance.LOC_BATTLE
	var can_discard := it.location == ItemInstance.LOC_BATTLE or it.location == ItemInstance.LOC_INVENTORY
	# 菜单层重建，只放适用项
	_menu_instance_id = it.instance_id
	_hide_context_menu()
	if _menu_layer == null:
		return
	for c in _menu_layer.get_children():
		_menu_layer.remove_child(c)
		c.queue_free()
	var items_r := SystemSkin.region(SystemSkin.CONTEXT_MENU, "items")
	var rows: Array = []
	if can_use:
		rows.append({"label": "使用", "cb": _on_menu_use, "enabled": true})
	if can_discard:
		rows.append({"label": "丢弃", "cb": _on_menu_discard, "enabled": true})
	if rows.is_empty():
		rows.append({"label": "无可用操作", "cb": Callable(), "enabled": false})
	var row_h := items_r.size.y / maxi(rows.size(), 1)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var b := UiKit.abs_button(String(r["label"]),
			(Callable(r["cb"]) if (r["cb"] as Callable).is_valid() else Callable()),
			Rect2i(items_r.position.x, items_r.position.y + int(i * row_h) + 2,
				items_r.size.x, maxi(int(row_h) - 4, 8)), 12)
		b.disabled = not bool(r["enabled"])
		_menu_layer.add_child(b)
	var size: Vector2 = _menu_layer.size
	var cell_local: Vector2 = _design_canvas.to_local(cell.global_position)
	var pos: Vector2 = cell_local + Vector2(8, 6)
	pos.x = minf(pos.x, _design_canvas.size.x - size.x - 4.0)
	pos.y = minf(pos.y, _design_canvas.size.y - size.y - 4.0)
	_menu_layer.position = pos
	_menu_layer.visible = true


# ---------------------------------------------------------------------------
# 拖拽状态机
# ---------------------------------------------------------------------------

## 拖拽起手：记录来源、淡影原格、生成跟随鼠标的预览。
## 移动与释放由原 cell 的 gui_input 继续处理（Godot 按钮捕获鼠标按钮期间持续路由）。
func _begin_drag(it: ItemInstance, where: String, cell: Button) -> void:
	if _drag_item != null:
		return
	_hide_tooltip()
	_hide_context_menu()
	_drag_item = it
	_drag_src = where
	_drag_cell = cell
	# 抓取点相对 cell 原点的偏移（设计画布局部坐标）
	_drag_offset = _design_canvas.get_local_mouse_position() - _design_canvas.to_local(cell.global_position)
	cell.modulate = Color(1, 1, 1, 0.35)  # 原位置保留淡影
	# 跟随鼠标的预览：用同款品质边框
	_drag_preview = _make_drag_preview(it, cell.size)
	_design_canvas.add_child(_drag_preview)
	_update_drag_preview()


func _make_drag_preview(it: ItemInstance, size: Vector2) -> Control:
	var def := catalog.item(it.definition_id)
	var p := Panel.new()
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.modulate = Color(1, 1, 1, 0.8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.18, 0.28, 0.8)
	style.set_border_width_all(2)
	style.border_color = UiKit.quality_color(it.quality)
	style.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", style)
	var name_str := def.display_name if def != null else String(it.definition_id)
	p.add_child(UiKit.abs_block(name_str, 11, UiKit.COL_SYS_TEXT,
		Rect2i(3, 3, maxi(int(size.x) - 6, 8), maxi(int(size.y) - 18, 8))))
	return p


## 更新拖拽预览位置与落点检测。
func _update_drag_preview() -> void:
	if _drag_preview == null:
		return
	var mouse := _design_canvas.get_local_mouse_position()
	_drag_preview.position = mouse - _drag_offset
	# 落点检测：鼠标是否在某个栏上（用全局坐标比较）
	_detect_drop(get_global_mouse_position())


## 检测当前鼠标位置对应的落点栏与格位，更新合法/非法预览。
func _detect_drop(mouse: Vector2) -> void:
	_drop_field = null
	_drop_index = -1
	_drop_valid = false
	_drop_reason = ""
	var dst := ""
	if _bb_field != null and _point_in(_bb_field, mouse):
		_drop_field = _bb_field
		dst = "bar"
	elif _inv_field != null and _point_in(_inv_field, mouse):
		_drop_field = _inv_field
		dst = "inv"
	_clear_drop_ghost()
	if _drop_field == null:
		return
	# 目标格位：鼠标 x 相对栏左沿换算
	var local := mouse - _drop_field.global_position
	var slot_w := _drop_field.size.x / 10.0
	_drop_index = int(clampf(floorf(local.x / slot_w), 0.0, 9.0))
	# 合法性：跨栏移动的装备约束 + 容量校验
	var res := _validate_drop(dst, _drop_index)
	_drop_valid = res["valid"]
	_drop_reason = String(res["reason"])
	_show_drop_ghost(dst, _drop_index, _drop_valid)


## 校验落点：构造目标序列，判断装备约束与最终容量。
func _validate_drop(dst: String, target_index: int) -> Dictionary:
	if _drag_item == null:
		return {"valid": false, "reason": "无拖拽物品"}
	var it := _drag_item
	var def := catalog.item(it.definition_id)
	if dst == "bar" and _drag_src == "inv":
		if def == null or not def.equippable:
			return {"valid": false, "reason": "该物品不能放入战斗栏"}
		if def.category == ItemDef.CAT_CONSUMABLE:
			return {"valid": false, "reason": "恢复品不进入战斗栏"}
	# 构造目标序列校验容量（复用服务层 move_item 的容量逻辑，但不真正提交）
	var new_bar: Array = ctrl.state.battle_bar.duplicate()
	var new_inv: Array = ctrl.state.inventory.duplicate()
	new_bar.erase(it)
	new_inv.erase(it)
	var arr := new_bar if dst == "bar" else new_inv
	ctrl.inventory._insert_at(arr, it, target_index)
	if not ctrl.state.fits_after(new_bar, new_inv):
		return {"valid": false, "reason": "目标栏空间不足"}
	return {"valid": true, "reason": ""}


## 显示落点预览：合法浅蓝、非法红，宽度按占格。
func _show_drop_ghost(dst: String, index: int, valid: bool) -> void:
	_clear_drop_ghost()
	if _drop_field == null or _drag_item == null:
		return
	var span := maxi(_drag_item.size(catalog), 1)
	var slot_w := _drop_field.size.x / 10.0
	var lo := roundf(index * slot_w)
	var hi := roundf((index + span) * slot_w)
	if hi > _drop_field.size.x:
		hi = _drop_field.size.x
	var rect := Rect2(lo, 0, maxf(hi - lo, 1.0), _drop_field.size.y)
	_drop_ghost = ColorRect.new()
	_drop_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_ghost.color = Color(0.55, 0.85, 1.0, 0.35) if valid else Color(0.95, 0.35, 0.35, 0.40)
	var field_local: Vector2 = _design_canvas.to_local(_drop_field.global_position)
	_drop_ghost.position = field_local + rect.position
	_drop_ghost.size = rect.size
	_design_canvas.add_child(_drop_ghost)


func _clear_drop_ghost() -> void:
	if _drop_ghost != null and is_instance_valid(_drop_ghost):
		_drop_ghost.queue_free()
	_drop_ghost = null


func _point_in(control: Control, pos: Vector2) -> bool:
	var r := Rect2(control.global_position, control.size)
	return r.has_point(pos)


## 拖拽结束：提交或取消。失败完整恢复原状。
func _finish_drag(commit: bool) -> void:
	if _drag_item == null:
		return
	var it := _drag_item
	var src := _drag_src
	var dst := ""
	if _drop_field == _bb_field:
		dst = "bar"
	elif _drop_field == _inv_field:
		dst = "inv"
	var index := _drop_index
	# 清理拖拽 UI
	if _drag_cell != null and is_instance_valid(_drag_cell):
		_drag_cell.modulate = Color.WHITE
	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_clear_drop_ghost()
	_drag_preview = null
	_drag_item = null
	_drag_cell = null
	_drop_field = null
	_drop_index = -1
	_drop_valid = false

	if not commit:
		_toast("已取消拖动")
		_refresh()
		return
	# 未落到有效栏：取消
	if dst == "":
		_toast("已取消拖动")
		_refresh()
		return
	# 提交移动（服务层原子校验，失败自动回退）
	var res := ctrl.move_item(it.instance_id, src, dst, index)
	if res.success:
		_toast("已移动")
	else:
		_toast(res.reason)
	_refresh()


## 技能栏：单行圆形图标，溢出时悬停滚轮横向浏览 + 两侧箭头（仅溢出时显示）。
## 内容放进一个横向内容条，通过 _skill_offset 平移实现横向浏览。
func _layout_skills(skills: Dictionary) -> void:
	if _skill_holder == null:
		return
	for c in _skill_holder.get_children():
		_skill_holder.remove_child(c)
		c.queue_free()
	_skill_items.clear()
	_skill_offset = 0.0
	if skills.is_empty():
		_skill_holder.add_child(UiKit.abs_sys_label("无技能", 11,
			Rect2i(0, _skill_holder.size.y / 2 - 9, _skill_holder.size.x, 18),
			UiKit.COL_SYS_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return

	var radius := mini(_skill_holder.size.y - 4, 32) / 2.0
	var spacing := radius * 2 + 6
	var x := 2.0
	for k in skills.keys():
		var ss: SkillState = skills[k]
		var slot := UiKit.abs_sys_skill_slot(
			Rect2i(int(x), int(_skill_holder.size.y / 2 - radius),
				int(radius * 2), int(radius * 2)),
			ss.quality)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.mouse_entered.connect(_on_skill_hover.bind(StringName(k), ss))
		slot.mouse_exited.connect(_on_skill_unhover)
		_skill_holder.add_child(slot)
		_skill_items.append({"skill_id": StringName(k), "node": slot})
		x += spacing

	var content_w := x
	var view_w := _skill_holder.size.x
	# 溢出时才有滚动：内容宽超出视口宽才显示箭头
	if content_w > view_w + 1.0:
		_skill_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		_skill_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_skill_scroll()


## 技能栏横向滚动偏移（滚轮与箭头共用），并同步箭头显隐与内容平移。
func _update_skill_scroll() -> void:
	if _skill_holder == null or _skill_items.is_empty():
		return
	# 计算内容总宽（最后一个技能右缘）
	var last: Control = _skill_items[-1]["node"]
	var content_w := last.position.x + last.size.x + 2.0
	var view_w := _skill_holder.size.x
	var max_off := maxf(content_w - view_w, 0.0)
	_skill_offset = clampf(_skill_offset, 0.0, max_off)
	for entry in _skill_items:
		(entry["node"] as Control).position.x -= 0.0  # 保持节点自身坐标，用父容器偏移
	# 用一个内部 holder 平移更干净，但这里直接对每个技能加统一偏移量
	# 为简单起见，记录基准 x 并重排：
	var radius := mini(_skill_holder.size.y - 4, 32) / 2.0
	var spacing := radius * 2 + 6
	var x := 2.0 - _skill_offset
	for entry in _skill_items:
		(entry["node"] as Control).position.x = int(x)
		x += spacing
	_update_skill_arrows(max_off > 0.0)


## 两侧箭头：仅溢出时显示，点击平移一档。
func _update_skill_arrows(overflow: bool) -> void:
	if _skill_holder == null:
		return
	if not overflow:
		if _skill_left_arrow != null:
			_skill_left_arrow.visible = false
		if _skill_right_arrow != null:
			_skill_right_arrow.visible = false
		return
	# 箭头画在技能区两侧（绝对定位，不占技能内容空间）
	if _skill_left_arrow == null:
		var sk_rect := SystemSkin.region_abs(SystemSkin.STATUS_PANEL, "skills")
		_skill_left_arrow = _make_arrow("<", -1)
		_skill_left_arrow.position = Vector2(sk_rect.position.x - 16, sk_rect.position.y + sk_rect.size.y / 2 - 12)
		_skill_right_arrow = _make_arrow(">", 1)
		_skill_right_arrow.position = Vector2(sk_rect.position.x + sk_rect.size.x + 4, sk_rect.position.y + sk_rect.size.y / 2 - 12)
		_design_canvas.add_child(_skill_left_arrow)
		_design_canvas.add_child(_skill_right_arrow)
	_skill_left_arrow.visible = true
	_skill_right_arrow.visible = true


func _make_arrow(text: String, direction: int) -> Button:
	var b := UiKit.abs_sys_button(text, _scroll_skill.bind(direction), Rect2i(0, 0, 24, 24), 13)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _scroll_skill(direction: int) -> void:
	var radius := mini(_skill_holder.size.y - 4, 32) / 2.0
	_skill_offset += direction * (radius * 2 + 6)
	_update_skill_scroll()


## 技能栏滚轮横向浏览（仅当鼠标悬停在技能区时）。
func _on_skill_wheel(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_skill(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_skill(1)


## 切换交互目标：Q 循环附近交互对象
func cycle_target() -> void:
	if _nearby.is_empty():
		_toast("无附近可交互对象")
		return
	# 将第一个移到最后，依次轮转
	var first := _nearby[0]
	_nearby.erase(first)
	_nearby.append(first)
	_update_prompt()
	_toast("Q：已切换目标")


## 显示短提示（2 秒消失）
func _toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	# 用 SceneTree timer 而非 await：无画面脚本模式 SceneTree 仍然可用
	var tree := get_tree()
	if tree != null:
		tree.create_timer(2.0).timeout.connect(_hide_toast)


func _hide_toast() -> void:
	if _toast_label != null:
		_toast_label.visible = false


# ---------------------------------------------------------------------------
# 房间格线（用于状态栏与背包栏的格线绘制）
# ---------------------------------------------------------------------------

## 单位格与格线：格宽 = 横栏净宽 ÷ 槽位数，物品边框不得改变单位格宽。
## 复用 panel_inventory.SlotField 的绘制方式，但用于系统组件叠加层。
class SlotField:
	extends Control

	var slot_count := 10
	var line_color := Color(0.82, 0.93, 1.0, 0.20)
	var outline_color := Color(0.78, 0.92, 1.0, 0.35)

	func _draw() -> void:
		var n := maxi(slot_count, 1)
		var w := size.x / float(n)
		for i in range(n + 1):
			var x := roundf(i * w)
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), line_color, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), outline_color, false, 1.0)


# ---------------------------------------------------------------------------
# 右侧动作面板（开发用，辅助测试与点击交互）
# ---------------------------------------------------------------------------

func _fill_actions() -> void:
	if _actions_box == null:
		return
	for c in _actions_box.get_children():
		_actions_box.remove_child(c)
		c.queue_free()
	_actions_box.add_child(UiKit.label("可交互对象", 13, UiKit.COL_ACCENT))
	if _specs.is_empty():
		_specs = interactable_specs()
	for spec in _specs:
		var disabled := bool(spec.get("done", false)) and String(spec.get("kind", "")) == "enemy"
		var b := UiKit.button(String(spec.get("label", "")), _activate.bind(spec), disabled)
		_actions_box.add_child(b)
	_actions_box.add_child(UiKit.spacer(6))
	_actions_box.add_child(UiKit.button("信息页（M）", func() -> void: ctrl.open_world_map()))
	_actions_box.add_child(UiKit.button("构筑整理", func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP)))
	var can_ret := ctrl.world.can_return(ctrl.state)
	var ret_btn := UiKit.button("回归主神", _on_return, not can_ret.success)
	_actions_box.add_child(ret_btn)
	if not can_ret.success:
		_actions_box.add_child(UiKit.label(can_ret.reason, 11, UiKit.COL_MUTED))
	_actions_box.add_child(UiKit.spacer(6))
	_actions_box.add_child(UiKit.button("认输", _surrender))


func _on_return() -> void:
	ctrl.return_to_deity()


func _fill_info() -> void:
	if _info_box == null:
		return
	for c in _info_box.get_children():
		_info_box.remove_child(c)
		c.queue_free()
	var state := ctrl.state
	_info_box.add_child(UiKit.label("任务/情报", 13, UiKit.COL_ACCENT))
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
		var mark := "主" if qdef.is_main else "支"
		_info_box.add_child(UiKit.label("[%s]%s:%s" % [mark, qdef.display_name, status], 12, UiKit.COL_TEXT))
	var intel := PackedStringArray()
	if state.known_intel.has("bandit_area"):
		intel.append("土匪区域已知")
	if state.known_intel.has("chief_node"):
		intel.append("头子位置已知")
	_info_box.add_child(UiKit.label("情报:%s" % ("、".join(intel) if intel.size() > 0 else "无"), 12, UiKit.COL_MUTED))
	_info_box.add_child(UiKit.label("下一节点费:%d" % ctrl.world.next_fee_preview(state), 12, UiKit.COL_MUTED))
