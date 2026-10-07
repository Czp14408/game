class_name PageBattle
extends PageBase
## 自动战斗表现：按组件化固定布局还原战斗界面，固定步长推进并实时刷新数值。
## 边界：只驱动 CombatEngine 与显示结果；结算通过 RunController 提交，本页不修改任何战斗数据。
## 依据：战斗UI组件与组合说明.md §1–§2（组件与排布表）、游戏可玩原型技术方案.md 第 7 节。
##
## 布局：设计画布 1280×690 —— 即 1280×720 逻辑画布减去顶部 30 像素状态条。
## 面板纹理与矩形全部来自 BattleSkin（由生成器产出），本页不写死坐标；
## 整个设计画布放在居中容器里，窗口比例变化时整体居中，坐标不漂移。

const LOG_LINES := 16
const SLOT_COUNT := 10

## 开场前几秒双方物品都还在初始冷却，日志区空着会让人以为界面坏了。
const _EMPTY_LOG_HINT := "（尚无事件：双方物品仍在初始冷却，倒计时结束后开始出手）"

## 头像内腔里立绘四周留出的余量，避免贴住内沿
const PORTRAIT_INNER_GAP := 2


## 十格战斗栏：只画单位格与格线，物品控件作为子节点按占格落位。
## 为什么单独一个控件：格宽 = 内腔净宽 ÷ 10，物品边框不得改变单位格宽，
## 所以格线必须由界面按净宽换算，不能随物品宽度伸缩。
class SlotField:
	extends Control

	var slot_count := 10
	var line_color := Color(0.60, 0.45, 0.27, 0.60)
	var outline_color := Color(0.06, 0.07, 0.09, 0.55)

	func _draw() -> void:
		var n := maxi(slot_count, 1)
		var w := size.x / float(n)
		for i in range(n + 1):
			var x := roundf(i * w)
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), line_color, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), outline_color, false, 1.0)

	## 第 index 格起、跨 span 格的矩形（相对本控件）
	func cell_rect(index: int, span: int) -> Rect2:
		var n := maxi(slot_count, 1)
		var w := size.x / float(n)
		var lo := clampi(index, 0, n)
		var hi := clampi(index + maxi(span, 1), 0, n)
		var x0 := roundf(lo * w)
		var x1 := roundf(hi * w)
		return Rect2(x0, 0.0, maxf(x1 - x0, 1.0), size.y)


class BattleSide:
	var key := BattleSkin.SIDE_PLAYER
	var color := Color.WHITE
	var name_label: Label
	var status_label: Label
	var skill_label: Label
	var hp_fill: ColorRect
	var shield_fill: ColorRect
	var hp_text: Label
	var hp_inner := Rect2()
	var slots: SlotField
	var cells: Array = []


var _engine: CombatEngine
var _is_stage := false
var _acc := 0.0
var _rate := 1.0
var _paused := false
var _settled := false

## 结果阶段：战斗结束后停留在本界面，展示胜负与掉落（§3）。
var _result_phase := false
var _result_summary: Dictionary = {}
var _drop_holder: Control = null       ## 掉落居中展示区（清空后的敌方物品栏）
var _result_hint: Label = null         ## 中央胜负提示
var _exit_btn: Button = null           ## 结果阶段的「退出战斗」

var _canvas: Control
var _clock: Label
var _ops_kind: Label
var _ops_step: Label
var _ops_state: Label
var _log_text: RichTextLabel
var _pause_layer: Control
var _stats_drawer: Control          ## 统计抽屉（battle_statistics 面板，默认隐藏）
var _stats_text: RichTextLabel      ## 统计数字区
var _stats_events: RichTextLabel    ## 事件流水区
var _stats_visible := false
var _stats_event_count := -1        ## 与日志同款：事件数没变就不重排
var _item_names: Dictionary = {}
var _log_event_count := -1
var _player_side := BattleSide.new()
var _enemy_side := BattleSide.new()


func build() -> void:
	_is_stage = bool(payload.get("stage", false))
	_engine = ctrl.active_engine

	# 页面区第一层必须是铺满宽度的容器：真渲染布局断言据此判断页面没被压窄。
	var center := CenterContainer.new()
	center.name = "BattleCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_canvas = Control.new()
	_canvas.name = "DesignCanvas"
	var design := BattleSkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_canvas.custom_minimum_size = Vector2(design)
	center.add_child(_canvas)
	_canvas.add_child(UiKit.solid(UiKit.COL_BG, Rect2i(Vector2i.ZERO, design)))

	if _engine == null:
		_canvas.add_child(UiKit.abs_label("战斗引擎缺失，无法开始。", 16, UiKit.COL_ENEMY,
			Rect2i(40, 40, 600, 30)))
		_canvas.add_child(UiKit.abs_button("返回", func() -> void: ctrl.close_battle(),
			Rect2i(40, 80, 140, 34)))
		return

	for a in [_engine.player_actor(), _engine.enemy_actor()]:
		if a == null:
			continue
		for it in a.items:
			_item_names[it.instance_id] = it.display_name

	_build_panels()
	_build_side(_player_side, BattleSkin.SIDE_PLAYER, _engine.player_actor(), true)
	_build_side(_enemy_side, BattleSkin.SIDE_ENEMY, _engine.enemy_actor(), false)
	_build_middle()
	_build_operations()
	_build_pause_layer()
	_build_stats_drawer()
	_refresh_view()
	set_process(true)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

## 静态面板底板：按 manifest 的矩形逐张 1:1 落位。先加，所以位于所有内容之下。
func _build_panels() -> void:
	for panel in BattleSkin.panel_names():
		if panel == BattleSkin.MODAL:
			continue
		var r := BattleSkin.rect(panel)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var art := UiKit.panel_art(BattleSkin.texture(panel), r)
		art.name = "Panel_%s" % panel
		_canvas.add_child(art)


func _build_side(view: BattleSide, key: String, actor: CombatActor, is_player: bool) -> void:
	view.key = key
	view.color = UiKit.COL_PLAYER if is_player else UiKit.COL_ENEMY

	_build_portrait(key, is_player)
	_build_name(view, key, actor)
	_build_status(view, key)
	_build_skill(view, key)
	_build_health(view, key)
	_build_tray(view, key, actor)


func _build_portrait(key: String, is_player: bool) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.PORTRAIT, key)
	var inner := BattleSkin.inner(panel)
	var box := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)
	var holder := Control.new()
	holder.name = "Portrait_%s" % key
	holder.position = Vector2(box.position)
	holder.size = Vector2(box.size)
	_canvas.add_child(holder)
	if is_player:
		var gap := Vector2i(PORTRAIT_INNER_GAP, PORTRAIT_INNER_GAP)
		var avatar := UiKit.pixel_art(HeroArt.pose(HeroArt.POSE_BATTLE), Vector2(box.size - gap * 2))
		avatar.name = "HeroAvatar"
		avatar.position = Vector2(gap)
		avatar.size = Vector2(box.size - gap * 2)
		holder.add_child(avatar)
		return
	# 对手形象尚未提供：放明确标注的占位，不假装是成品。
	holder.name = "EnemyPortraitPlaceholder"
	holder.add_child(UiKit.overlay(Color(0.09, 0.10, 0.13, 0.92), Vector2(box.size)))
	holder.add_child(UiKit.abs_label("敌", 42, UiKit.COL_ENEMY,
		Rect2i(0, box.size.y / 2 - 34, box.size.x, 44), HORIZONTAL_ALIGNMENT_CENTER))
	holder.add_child(UiKit.abs_label("对手形象待补", 11, UiKit.COL_MUTED,
		Rect2i(0, box.size.y / 2 + 10, box.size.x, 18), HORIZONTAL_ALIGNMENT_CENTER))


func _build_name(view: BattleSide, key: String, actor: CombatActor) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.NAME, key)
	var inner := BattleSkin.inner(panel)
	var rect := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)
	var text := actor.display_name if actor != null else "？"
	view.name_label = UiKit.abs_label(text, 14, UiKit.COL_ACCENT, rect, HORIZONTAL_ALIGNMENT_CENTER)
	view.name_label.name = "Name_%s" % key
	_canvas.add_child(view.name_label)


func _build_status(view: BattleSide, key: String) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.STATUS, key)
	var inner := BattleSkin.inner(panel)
	var rect := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)
	view.status_label = UiKit.abs_block("", 12, UiKit.COL_TEXT, rect)
	view.status_label.name = "Status_%s" % key
	_canvas.add_child(view.status_label)


func _build_skill(view: BattleSide, key: String) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.SKILL, key)
	var inner := BattleSkin.inner(panel)
	var rect := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)
	view.skill_label = UiKit.abs_label("", 14, UiKit.COL_TEXT, rect)
	view.skill_label.name = "Skill_%s" % key
	_canvas.add_child(view.skill_label)


func _build_health(view: BattleSide, key: String) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.HEALTH, key)
	var inner := BattleSkin.inner(panel)
	var rect := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)
	view.hp_inner = Rect2(rect)

	# 生命填充从左侧生长，护盾从右侧生长，二者都限制在生命槽内腔里。
	view.hp_fill = UiKit.solid(view.color.darkened(0.15), Rect2i(rect.position, Vector2i(0, rect.size.y)))
	view.hp_fill.name = "HealthFill_%s" % key
	_canvas.add_child(view.hp_fill)

	view.shield_fill = UiKit.solid(UiKit.COL_SHIELD, Rect2i(rect.position, Vector2i(0, rect.size.y)))
	view.shield_fill.name = "ShieldFill_%s" % key
	_canvas.add_child(view.shield_fill)

	view.hp_text = UiKit.abs_label("", 12, UiKit.COL_TEXT, rect, HORIZONTAL_ALIGNMENT_CENTER)
	view.hp_text.name = "HealthText_%s" % key
	view.hp_text.add_theme_constant_override("outline_size", 4)
	view.hp_text.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.07, 0.9))
	_canvas.add_child(view.hp_text)


func _build_tray(view: BattleSide, key: String, actor: CombatActor) -> void:
	var panel := BattleSkin.side_panel(BattleSkin.TRAY, key)
	var inner := BattleSkin.inner(panel)
	var rect := Rect2i(BattleSkin.rect(panel).position + inner.position, inner.size)

	view.slots = SlotField.new()
	view.slots.name = "Slots_%s" % key
	view.slots.slot_count = SLOT_COUNT
	view.slots.position = Vector2(rect.position)
	view.slots.size = Vector2(rect.size)
	view.slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(view.slots)

	if actor == null:
		return
	var cell_index := 0
	for it in actor.items:
		var box := view.slots.cell_rect(cell_index, it.size)
		var row := _make_item_cell(it, box, key, cell_index)
		view.cells.append(row)
		view.slots.add_child(row["node"])
		cell_index += it.size
	view.slots.queue_redraw()


## 单件物品的单位格控件：品质边框、名称、占格与释放次数、冷却条、冻结减速覆盖层。
## 依据 §2.1：单位格宽由净宽换算，物品边框不改变格宽；冷却与冻结减速均为独立覆盖层。
## 返回控件与其子节点的引用集合，供 _refresh_item_cell 增量刷新，避免每帧重建。
func _make_item_cell(item: BattleItemState, box: Rect2, key: String, index: int) -> Dictionary:
	var cell := Panel.new()
	cell.name = "Item_%s_%d" % [key, index]
	cell.position = box.position
	cell.size = box.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.17, 0.88)
	style.set_border_width_all(2)
	style.border_color = UiKit.quality_color(item.quality)
	style.set_corner_radius_all(3)
	cell.add_theme_stylebox_override("panel", style)

	var w := int(box.size.x)
	var h := int(box.size.y)
	var pad := 5
	var inner_w := maxi(w - pad * 2, 8)

	cell.add_child(UiKit.abs_block(item.display_name, 13, UiKit.COL_TEXT, Rect2i(pad, 4, inner_w, 36)))
	cell.add_child(UiKit.abs_label("%s·%d格" % [PriceTable.quality_name(item.quality), item.size],
		11, UiKit.quality_color(item.quality), Rect2i(pad, 42, inner_w, 15)))
	var uses_l := UiKit.abs_label("", 11, UiKit.COL_MUTED, Rect2i(pad, 58, inner_w, 15))
	cell.add_child(uses_l)

	var bar_h := 7
	var bar_wrap := Control.new()
	bar_wrap.name = "Cooldown"
	bar_wrap.position = Vector2(pad, h - 30)
	bar_wrap.size = Vector2(inner_w, bar_h)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 先底槽后填充：冷却进度按「恢复到可用」的比例从左向右生长
	bar_wrap.add_child(UiKit.overlay(Color(0.05, 0.06, 0.08, 0.9), Vector2(inner_w, bar_h)))
	var bar := UiKit.overlay(UiKit.COL_ACCENT, Vector2(0, bar_h))
	bar.name = "Fill"
	bar_wrap.add_child(bar)
	cell.add_child(bar_wrap)
	var cd_l := UiKit.abs_label("", 11, UiKit.COL_MUTED, Rect2i(pad, h - 20, inner_w, 14))
	cell.add_child(cd_l)

	# 冻结／减速／加速覆盖层：整格染色，独立于冷却条，两种状态不会互相遮蔽。
	var overlay := UiKit.overlay(Color(0, 0, 0, 0), Vector2(box.size))
	overlay.name = "ControlOverlay"
	overlay.visible = false
	cell.add_child(overlay)

	# 冷却中整格压暗，让「现在能放什么」一眼可见。
	var dim := UiKit.overlay(Color(0.02, 0.03, 0.05, 0.45), Vector2(box.size))
	dim.name = "CooldownDim"
	dim.visible = false
	cell.add_child(dim)

	return {"node": cell, "item": item, "uses": uses_l, "cd": cd_l, "bar": bar,
		"bar_width": float(inner_w), "overlay": overlay, "dim": dim}


func _build_middle() -> void:
	var inner := BattleSkin.inner(BattleSkin.MIDDLE)
	var rect := Rect2i(BattleSkin.rect(BattleSkin.MIDDLE).position + inner.position, inner.size)
	_clock = UiKit.abs_label("", 14, UiKit.COL_TEXT, rect, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.name = "BattleClock"
	_canvas.add_child(_clock)


## 右侧操作栏：顶部战斗状态、中部操作与战斗记录、底部退出。
## 三段边界取 operations 面板的可用条带（素材自带两处分隔），不靠内腔上下界推算。
func _build_operations() -> void:
	var panel_rect := BattleSkin.rect(BattleSkin.OPERATIONS)
	var inner := BattleSkin.inner(BattleSkin.OPERATIONS)
	# 左右各留 2 像素：按钮描边贴着内沿时会与古铜内框连成一片
	var x := panel_rect.position.x + inner.position.x + 2
	var w := inner.size.x - 4
	var bands := BattleSkin.bands_h(BattleSkin.OPERATIONS)
	var top_y := panel_rect.position.y + _band_start(bands, 0, inner.position.y - 16 - 2)
	var top_h := _band_size(bands, 0, inner.position.y - 18)
	var mid_y := panel_rect.position.y + _band_start(bands, 1, inner.position.y)
	var mid_h := _band_size(bands, 1, inner.size.y)
	var btm_y := panel_rect.position.y + _band_start(bands, 2, inner.position.y + inner.size.y)
	var btm_h := _band_size(bands, 2, panel_rect.size.y - inner.position.y - inner.size.y - 19)

	# 顶部：战斗类型、步数与状态。三行都留出分隔条的余量。
	_ops_kind = UiKit.abs_label("", 13, UiKit.COL_ACCENT, Rect2i(x, top_y + 2, w, 16))
	_ops_kind.name = "OpsKind"
	_canvas.add_child(_ops_kind)
	_ops_step = UiKit.abs_label("", 11, UiKit.COL_TEXT, Rect2i(x, top_y + 18, w, 15))
	_ops_step.name = "OpsStep"
	_canvas.add_child(_ops_step)
	_ops_state = UiKit.abs_label("", 11, UiKit.COL_MUTED, Rect2i(x, top_y + 33, w, 15))
	_ops_state.name = "OpsState"
	_canvas.add_child(_ops_state)

	# 中部：操作按钮 + 战斗记录
	var btn_gap := 6
	var y := mid_y + 2
	var speed_w := (w - btn_gap * 2) / 3
	var rates := [1, 2, 4]
	for i in rates.size():
		# 最后一格吃掉整除余数，避免第三个按钮越过面板右沿
		var bw := w - (speed_w * 2 + btn_gap * 2) if i == rates.size() - 1 else speed_w
		var bx := x + i * (speed_w + btn_gap)
		_canvas.add_child(UiKit.abs_button("×%d" % rates[i], _set_rate.bind(float(rates[i])),
			Rect2i(bx, y, bw, 26), 12))
	y += 26 + btn_gap
	_canvas.add_child(UiKit.abs_button("暂停／继续（Esc）", _toggle_pause, Rect2i(x, y, w, 28), 12))
	y += 28 + btn_gap
	_canvas.add_child(UiKit.abs_button("单步（F）", _single_step, Rect2i(x, y, w, 28), 12))
	y += 28 + btn_gap
	_canvas.add_child(UiKit.abs_button("瞬间算完", fast_forward, Rect2i(x, y, w, 28), 12))
	y += 28 + btn_gap + 4

	_canvas.add_child(UiKit.abs_label("战斗记录（最近 %d 条）" % LOG_LINES, 12, UiKit.COL_ACCENT,
		Rect2i(x, y, w, 17)))
	y += 19
	var log_h := maxi(mid_y + mid_h - y - 6, 40)
	# 用自带滚动的 RichTextLabel，而不是 Label + ScrollContainer：
	# 后者会把这条 191 像素宽的日志压成一行高，内容再全也看不见（实测 191×1）。
	# 正文左右各内缩 6 像素：富文本没有自带内边距，满宽排会顶到内框竖线上。
	_log_text = UiKit.abs_log(11, UiKit.COL_MUTED, Rect2i(x + 6, y, w - 12, log_h))
	_log_text.name = "BattleLog"
	_canvas.add_child(_log_text)

	# 底部：统计抽屉开关 + 退出
	var btm_w := (w - 6) / 2
	_canvas.add_child(UiKit.abs_button("战斗统计", _toggle_stats, Rect2i(x, btm_y + 2, btm_w, 30), 12))
	_canvas.add_child(UiKit.abs_button("主动认输并结束试炼", _surrender,
		Rect2i(x + btm_w + 6, btm_y + 2, w - btm_w - 6, 30), 12))
	_canvas.add_child(UiKit.abs_block("认输后本局直接结束。战斗中不能整理、交易或使用战斗外恢复品。",
		11, UiKit.COL_MUTED, Rect2i(x, btm_y + 34, w, maxi(btm_h - 36, 16))))


func _band_start(bands: Array[Vector2i], index: int, fallback: int) -> int:
	return bands[index].x if index < bands.size() else fallback


func _band_size(bands: Array[Vector2i], index: int, fallback: int) -> int:
	return bands[index].y - bands[index].x if index < bands.size() else fallback


## 暂停遮罩 + 弹窗。弹窗沿用同一套组件素材，避免暗色圆角面板与木框拼在一起。
func _build_pause_layer() -> void:
	_pause_layer = Control.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.position = Vector2.ZERO
	_pause_layer.size = Vector2(BattleSkin.design_size())
	_pause_layer.visible = false
	_canvas.add_child(_pause_layer)
	_pause_layer.add_child(UiKit.overlay(Color(0.02, 0.02, 0.03, 0.62), Vector2(_pause_layer.size)))

	var modal := BattleSkin.rect(BattleSkin.MODAL)
	if modal.size.x <= 0:
		return
	var box := Rect2i((Vector2i(BattleSkin.design_size()) - modal.size) / 2, modal.size)
	var art := UiKit.panel_art(BattleSkin.texture(BattleSkin.MODAL), box)
	art.name = "PausePanel"
	_pause_layer.add_child(art)

	var inner := BattleSkin.inner(BattleSkin.MODAL)
	var x := box.position.x + inner.position.x
	var y := box.position.y + inner.position.y
	var w := inner.size.x
	_pause_layer.add_child(UiKit.abs_label("战斗暂停", 18, UiKit.COL_ACCENT, Rect2i(x, y, w, 26)))
	_pause_layer.add_child(UiKit.abs_label("暂停期间战斗时钟停止，不积累时间步。", 13, UiKit.COL_MUTED,
		Rect2i(x, y + 34, w, 20)))
	_pause_layer.add_child(UiKit.abs_label("战斗中不能整理、交易、使用战斗外恢复品或中途退出到大地图。",
		13, UiKit.COL_MUTED, Rect2i(x, y + 56, w, 20)))
	var bw := (w - 10) / 2
	_pause_layer.add_child(UiKit.abs_button("继续战斗（Esc）", _toggle_pause, Rect2i(x, y + 96, bw, 34), 13))
	_pause_layer.add_child(UiKit.abs_button("主动认输并结束试炼", _surrender,
		Rect2i(x + bw + 10, y + 96, bw, 34), 13))


## 统计抽屉（battle_statistics 面板）：几何全部经 SystemSkin 读取，默认隐藏。
## 与暂停层同类：浮在战斗画布之上，不参与排布。
func _build_stats_drawer() -> void:
	var rect := SystemSkin.rect(SystemSkin.BATTLE_STATISTICS)
	if rect.size.x <= 0:
		return
	_stats_drawer = Control.new()
	_stats_drawer.name = "StatsDrawer"
	_stats_drawer.position = Vector2(rect.position)
	_stats_drawer.size = Vector2(rect.size)
	_stats_drawer.visible = false
	_canvas.add_child(_stats_drawer)
	var art := UiKit.nine_patch(SystemSkin.texture(SystemSkin.BATTLE_STATISTICS),
		Rect2i(Vector2i.ZERO, rect.size), SystemSkin.nine_patch_margins_ltrb(SystemSkin.BATTLE_STATISTICS))
	_stats_drawer.add_child(art)

	var stats_r := SystemSkin.region(SystemSkin.BATTLE_STATISTICS, "stats")
	var events_r := SystemSkin.region(SystemSkin.BATTLE_STATISTICS, "events")
	_stats_text = UiKit.abs_log(12, UiKit.COL_TEXT, Rect2i(stats_r.position, stats_r.size))
	_stats_text.name = "StatsNumbers"
	_stats_drawer.add_child(_stats_text)
	_stats_events = UiKit.abs_log(11, UiKit.COL_MUTED, Rect2i(events_r.position, events_r.size))
	_stats_events.name = "StatsEvents"
	_stats_drawer.add_child(_stats_events)


func _toggle_stats() -> void:
	_stats_visible = not _stats_visible
	if _stats_drawer != null:
		_stats_drawer.visible = _stats_visible
	if _stats_visible:
		_stats_event_count = -1  # 强制下次刷新重排
		_update_stats()


## 统计内容：从事件流聚合双方输出／治疗／用物次数。事件数没变就跳过重排。
func _update_stats() -> void:
	if _stats_text == null or _engine == null or not _stats_visible:
		return
	var events: Array = _engine.result().events
	if events.size() == _stats_event_count:
		return
	_stats_event_count = events.size()
	var dmg_out := 0.0
	var dmg_in := 0.0
	var heal_get := 0.0
	var uses := 0
	var storms := 0
	for raw in events:
		var ev: Dictionary = raw
		match String(ev.get("type", "")):
			"use_weapon":
				if int(ev.get("source_side", 0)) == CombatActor.SIDE_PLAYER:
					dmg_out += float(ev.get("actual", 0.0))
				else:
					dmg_in += float(ev.get("actual", 0.0))
			"heal":
				if int(ev.get("source_side", 0)) == CombatActor.SIDE_PLAYER:
					heal_get += float(ev.get("actual", 0.0))
			"use_item":
				uses += 1
			"storm":
				storms += 1
	var lines := PackedStringArray()
	lines.append("已进行 %d 步（约 %.1fs）　事件 %d 条" % [
		_engine.current_step(), float(_engine.current_step()) * CombatEngine.STEP_SECONDS, events.size()])
	lines.append("我方输出 %.1f　承伤 %.1f　治疗实得 %.1f" % [dmg_out, dmg_in, heal_get])
	lines.append("用物 %d 次　沙尘暴 %d 次" % [uses, storms])
	_stats_text.text = "\n".join(lines)
	# 事件流水：复用右栏格式化，取最近 8 条
	var recent := PackedStringArray()
	var i := events.size() - 1
	while i >= 0 and recent.size() < 8:
		var one := _format_event(events[i])
		if not one.is_empty():
			recent.append(one)
		i -= 1
	recent.reverse()
	_stats_events.text = "\n".join(recent) if not recent.is_empty() else "暂无事件。"


# ---------------------------------------------------------------------------
# 推进
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _engine == null or _settled or _paused:
		return
	_acc += delta * _rate
	var guard := 0
	while _acc >= CombatEngine.STEP_SECONDS and not _engine.is_finished() and guard < 600:
		_engine.step()
		_acc -= CombatEngine.STEP_SECONDS
		guard += 1
	_refresh_view()
	if _engine.is_finished():
		_finish()


func _set_rate(value: float) -> void:
	_rate = value
	_refresh_view()


func _toggle_pause() -> void:
	_paused = not _paused
	if _pause_layer != null:
		_pause_layer.visible = _paused
	_refresh_view()


func _single_step() -> void:
	if _engine == null or _settled:
		return
	_paused = true
	if _pause_layer != null:
		_pause_layer.visible = true
	_engine.step()
	_refresh_view()
	if _engine.is_finished():
		_finish()


func fast_forward() -> void:
	if _engine == null or _settled:
		return
	_engine.run_all()
	_refresh_view()
	_finish()


func _finish() -> void:
	if _settled:
		return
	_settled = true
	set_process(false)
	if _pause_layer != null:
		_pause_layer.visible = false
	if _is_stage:
		# 阶段战斗：结算后按既定阶段规则流转（胜利回整备/结果，失败回整备或结束）
		ctrl.settle_stage_battle(_engine)
		return
	# 普通世界战斗：结果与掉落留在本界面（§3 统一战斗界面）
	_result_summary = ctrl.settle_battle_inplace(_engine)
	_enter_result_phase()


## 进入结果阶段：显示胜负提示，清空敌方物品栏并居中展示唯一掉落（若有）。
## 点击掉落领取/学习；退出未领取默认放弃（阶段首领无掉落）。
func _enter_result_phase() -> void:
	_result_phase = true
	var win := _engine.result().winner_is_player()
	var es := ctrl.encounter_state()
	# 中央胜负提示
	var text := "胜利" if win else "失败"
	var col := UiKit.COL_MERCHANT if win else UiKit.COL_ENEMY
	var middle := BattleSkin.inner(BattleSkin.MIDDLE)
	var mrect := Rect2i(BattleSkin.rect(BattleSkin.MIDDLE).position + middle.position, middle.size)
	_result_hint = UiKit.abs_label("战斗%s" % text, 18, col, mrect, HORIZONTAL_ALIGNMENT_CENTER)
	_result_hint.name = "ResultHint"
	_canvas.add_child(_result_hint)

	# 清空敌方物品栏（复用 _enemy_side 的 slots 控件），居中展示掉落
	_clear_enemy_tray()
	_build_drop_display(es, win)

	# 结果阶段：右侧底部操作切换为「退出战斗」
	_build_result_exit()

	if _ops_kind != null:
		_ops_kind.text = "战斗结束"
	if _ops_state != null:
		_ops_state.text = "胜利" if win else "失败"
	_refresh_view()


## 清空敌方物品栏里的物品格（掉落居中展示前）。
func _clear_enemy_tray() -> void:
	if _enemy_side.slots == null:
		return
	for c in _enemy_side.slots.get_children():
		_enemy_side.slots.remove_child(c)
		c.queue_free()
	_enemy_side.cells.clear()


## 在清空后的敌方物品栏中央展示掉落：物品按实际占格，技能用独立卡牌样式。
func _build_drop_display(es: EncounterState, win: bool) -> void:
	if _enemy_side.slots == null:
		return
	var tray_rect := Rect2(_enemy_side.slots.position, _enemy_side.slots.size)
	_drop_holder = Control.new()
	_drop_holder.name = "DropHolder"
	_drop_holder.position = tray_rect.position
	_drop_holder.size = tray_rect.size
	_drop_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_drop_holder)

	if not win:
		_drop_holder.add_child(UiKit.abs_label("本场没有掉落", 14, UiKit.COL_MUTED,
			Rect2i(0, int(tray_rect.size.y / 2) - 10, int(tray_rect.size.x), 20), HORIZONTAL_ALIGNMENT_CENTER))
		return

	# 阶段首领无掉落（stage 战斗不走这里，但普通世界战斗可能无掉落）
	if es == null or (es.pending_drops.is_empty() and es.pending_skill.is_empty()):
		_drop_holder.add_child(UiKit.abs_label("本场没有掉落", 14, UiKit.COL_MUTED,
			Rect2i(0, int(tray_rect.size.y / 2) - 10, int(tray_rect.size.x), 20), HORIZONTAL_ALIGNMENT_CENTER))
		return

	# 技能掉落：独立卡牌样式（圆形），居中
	if not es.pending_skill.is_empty():
		_build_skill_drop(es.pending_skill)
		return

	# 物品掉落：按实际占格大小，居中
	var it: ItemInstance = es.pending_drops[0]
	_build_item_drop(it)


func _build_item_drop(it: ItemInstance) -> void:
	var slot_w := _enemy_side.slots.size.x / 10.0
	var span := maxi(it.size(catalog), 1)
	var w := slot_w * span
	var h := _enemy_side.slots.size.y
	var x := (_enemy_side.slots.size.x - w) / 2.0
	var box := Rect2(x, 0, w, h)
	var cell := Panel.new()
	cell.position = box.position
	cell.size = box.size
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.15, 0.22, 0.9)
	style.set_border_width_all(2)
	style.border_color = UiKit.quality_color(it.quality)
	style.set_corner_radius_all(3)
	cell.add_theme_stylebox_override("panel", style)
	var def := catalog.item(it.definition_id)
	cell.add_child(UiKit.abs_label("点击领取", 11, UiKit.COL_SYS_ACCENT,
		Rect2i(4, int(h) - 34, int(w) - 8, 14), HORIZONTAL_ALIGNMENT_CENTER))
	cell.add_child(UiKit.abs_block(def.display_name if def != null else String(it.definition_id),
		12, UiKit.COL_TEXT, Rect2i(4, 6, int(w) - 8, maxi(int(h) - 50, 12))))
	cell.add_child(UiKit.abs_label("%s·%d格" % [PriceTable.quality_name(it.quality), def.size if def != null else 1],
		10, UiKit.quality_color(it.quality), Rect2i(4, int(h) - 18, int(w) - 8, 14)))
	cell.gui_input.connect(_on_drop_item_click.bind(it))
	_drop_holder.add_child(cell)


func _build_skill_drop(skill: Dictionary) -> void:
	var box := Rect2(_enemy_side.slots.size.x / 2 - 60, 8, 120, _enemy_side.slots.size.y - 16)
	var cell := Button.new()
	cell.position = box.position
	cell.size = box.size
	cell.focus_mode = Control.FOCUS_NONE
	cell.text = ""
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.20, 0.30, 0.9)
	style.set_border_width_all(2)
	style.border_color = UiKit.quality_color(int(skill.get("quality", 0)))
	style.set_corner_radius_all(48)  # 圆形技能卡牌
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	cell.add_theme_stylebox_override("normal", style)
	cell.add_theme_stylebox_override("hover", style)
	cell.add_theme_stylebox_override("pressed", style)
	var sd := catalog.skill(StringName(skill.get("skill_id", "")))
	cell.add_child(UiKit.abs_label("技能·点击学习", 11, UiKit.COL_SYS_ACCENT,
		Rect2i(4, int(box.size.y) - 30, int(box.size.x) - 8, 14), HORIZONTAL_ALIGNMENT_CENTER))
	cell.add_child(UiKit.abs_label(sd.display_name if sd != null else String(skill.get("skill_id", "")),
		12, UiKit.COL_TEXT, Rect2i(4, 12, int(box.size.x) - 8, 30), HORIZONTAL_ALIGNMENT_CENTER))
	cell.add_child(UiKit.abs_label("%s" % PriceTable.quality_name(int(skill.get("quality", 0))),
		10, UiKit.quality_color(int(skill.get("quality", 0))), Rect2i(4, int(box.size.y) - 18, int(box.size.x) - 8, 14), HORIZONTAL_ALIGNMENT_CENTER))
	cell.gui_input.connect(_on_drop_skill_click)
	_drop_holder.add_child(cell)


func _on_drop_item_click(event: InputEvent, it: ItemInstance) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	# 直接拾取到背包（唯一掉落）；入包自动合成的结果合并为一次提示（§11）
	var res := ctrl.inventory.pickup(ctrl.state, it)
	if res.success:
		# 从 pending_drops 移除
		var es := ctrl.encounter_state()
		if es != null:
			es.pending_drops.erase(it)
		var merged := int(res.data.get("merged", 0))
		if merged > 0:
			_ctrl_toast("自动合成 ×%d → %s·%s" % [merged,
				PriceTable.quality_name(int(res.data.get("produced_quality", it.quality))),
				ctrl.catalog.item_display(it.definition_id)])
		else:
			_ctrl_toast("已领取 %s" % ctrl.catalog.item_display(it.definition_id))
		_rebuild_drop_display()
	else:
		_ctrl_toast(res.reason)


func _on_drop_skill_click(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var res := ctrl.resolve_skill_drop(true)
	_ctrl_toast("已学习技能" if res.success else res.reason)
	_rebuild_drop_display()


## 领取/学习后重建掉落展示（掉落已移除则显示空态）。
func _rebuild_drop_display() -> void:
	if _drop_holder != null and is_instance_valid(_drop_holder):
		_drop_holder.queue_free()
	_drop_holder = null
	var es := ctrl.encounter_state()
	_build_drop_display(es, true)


## 结果阶段的「退出战斗」：返回场景，未领取掉落默认放弃。
func _build_result_exit() -> void:
	if _ops_kind == null:
		return
	# 复用中部操作区上方位置放退出按钮（避免覆盖日志）
	var panel_rect := BattleSkin.rect(BattleSkin.OPERATIONS)
	var inner := BattleSkin.inner(BattleSkin.OPERATIONS)
	var x := panel_rect.position.x + inner.position.x + 2
	var w := inner.size.x - 4
	var bands := BattleSkin.bands_h(BattleSkin.OPERATIONS)
	var mid_y := panel_rect.position.y + _band_start(bands, 1, inner.position.y)
	_exit_btn = UiKit.abs_button("退出战斗（未领取默认放弃）", _on_exit_battle,
		Rect2i(x, mid_y + 2, w, 30), 12)
	_canvas.add_child(_exit_btn)


func _on_exit_battle() -> void:
	ctrl.leave_post_battle()


func _ctrl_toast(text: String) -> void:
	# 战斗页用操作栏状态行提示
	if _ops_state != null:
		_ops_state.text = text


func _surrender() -> void:
	_settled = true
	set_process(false)
	ctrl.surrender()


func _unhandled_input(event: InputEvent) -> void:
	# 页面已脱离界面或正在释放时不再响应输入（不用 is_inside_tree()，理由见 page_minimap.gd）。
	if get_parent() == null or is_queued_for_deletion():
		return
	if event.is_action_pressed("cancel"):
		_toggle_pause()
		consume_input()
	elif event.is_action_pressed("dev_step"):
		_single_step()
		consume_input()


# ---------------------------------------------------------------------------
# 显示
# ---------------------------------------------------------------------------

func _refresh_view() -> void:
	if _engine == null:
		return
	_refresh_side(_player_side, _engine.player_actor())
	_refresh_side(_enemy_side, _engine.enemy_actor())
	var secs := float(_engine.current_step()) * CombatEngine.STEP_SECONDS
	if _clock != null:
		var text := "已进行 %.1f 秒（第 %d 步）" % [secs, _engine.current_step()]
		if float(_engine.current_step()) >= float(CombatEngine.STORM_START_STEP):
			text += "　⚠ 沙尘暴已开始：跳过护盾，伤害逐秒提高"
		_clock.text = text
	if _ops_kind != null:
		_ops_kind.text = "阶段试炼" if _is_stage else "世界遭遇"
		_ops_step.text = "第 %d 步 · %.1f 秒" % [_engine.current_step(), secs]
		_ops_state.text = "%s · 倍速 ×%.0f" % ["已暂停" if _paused else "进行中", _rate]
	_update_log()
	_update_stats()


func _refresh_side(view: BattleSide, actor: CombatActor) -> void:
	if view == null or actor == null or view.hp_fill == null:
		return
	var ratio := clampf(actor.hp / maxf(actor.max_hp, 1.0), 0.0, 1.0)
	var shield_ratio := clampf(actor.shield / maxf(actor.max_hp, 1.0), 0.0, 1.0)
	view.hp_fill.size = Vector2(view.hp_inner.size.x * ratio, view.hp_inner.size.y)
	view.hp_fill.position = view.hp_inner.position
	view.shield_fill.size = Vector2(view.hp_inner.size.x * shield_ratio, view.hp_inner.size.y)
	view.shield_fill.position = Vector2(
		view.hp_inner.position.x + view.hp_inner.size.x - view.shield_fill.size.x,
		view.hp_inner.position.y)
	view.hp_text.text = "生命 %.1f / %.1f　护盾 %.1f" % [
		maxf(actor.hp, 0.0), actor.max_hp, maxf(actor.shield, 0.0)]

	# 状态面板只放数值型状态：护盾、灼烧、中毒与被动修正，一行一条。
	var parts := PackedStringArray()
	if actor.shield > 0.0:
		parts.append("护盾 %.1f" % actor.shield)
	if actor.total_burn() > 0.0:
		parts.append("灼烧 %.1f 层　每跳扣 %d" % [actor.total_burn(), 1])
	if actor.total_poison() > 0.0:
		parts.append("中毒 %.1f 层（绕过护盾）" % actor.total_poison())
	if actor.weapon_damage_flat != 0.0:
		parts.append("武器固定加成 +%.1f" % actor.weapon_damage_flat)
	if actor.heal_on_weapon_use > 0.0:
		parts.append("使用武器吸血 %.1f" % actor.heal_on_weapon_use)
	view.status_label.text = "\n".join(parts) if parts.size() > 0 else "无附加状态"

	# 技能栏独立于十格战斗栏，不占格数。
	if actor.skills.is_empty():
		view.skill_label.text = "技能：无（本局未获得）"
	else:
		var sk := PackedStringArray()
		for k in actor.skills.keys():
			sk.append("%s（%s）" % [catalog.skill_display(k), PriceTable.quality_name(int(actor.skills[k]))])
		view.skill_label.text = "技能：" + "　".join(sk)

	for row in view.cells:
		_refresh_item_cell(row)


func _refresh_item_cell(row: Dictionary) -> void:
	var it: BattleItemState = row["item"]
	var fill: ColorRect = row["bar"]
	var ready := 1.0
	if it.base_cd_ms > 0:
		ready = clampf(1.0 - float(maxi(it.cooldown_remaining_ms, 0)) / float(it.base_cd_ms), 0.0, 1.0)
	elif not it.is_ready():
		ready = 0.0
	fill.size = Vector2(float(row["bar_width"]) * ready, fill.size.y)
	fill.color = UiKit.COL_ACCENT if it.is_ready() else Color(0.55, 0.44, 0.30)

	var extra := PackedStringArray()
	if it.freeze_ms > 0:
		extra.append("冰冻 %.1fs" % (float(it.freeze_ms) / 1000.0))
	if it.slow_ms > 0:
		extra.append("减速 %.1fs" % (float(it.slow_ms) / 1000.0))
	if it.haste_ms > 0:
		extra.append("加速 %.1fs" % (float(it.haste_ms) / 1000.0))
	var detail := "释放 %d 次" % it.uses
	if it.battle_growth != 0.0:
		detail += "　成长 +%.1f" % it.battle_growth
	if extra.size() > 0:
		detail += "　" + "　".join(extra)
	(row["uses"] as Label).text = detail

	var state_text := "就绪"
	if it.is_frozen():
		state_text = "冰冻中"
	elif it.slow_ms > 0:
		state_text = "减速中"
	elif it.haste_ms > 0:
		state_text = "加速中"
	(row["cd"] as Label).text = "%s · 冷却 %.1fs / %.1fs" % [
		state_text, float(maxi(it.cooldown_remaining_ms, 0)) / 1000.0, float(it.base_cd_ms) / 1000.0]

	var overlay: ColorRect = row["overlay"]
	overlay.visible = it.freeze_ms > 0 or it.slow_ms > 0 or it.haste_ms > 0
	if it.freeze_ms > 0:
		overlay.color = Color(0.45, 0.75, 1.0, 0.22)
	elif it.slow_ms > 0:
		overlay.color = Color(0.35, 0.45, 0.85, 0.18)
	else:
		overlay.color = Color(0.95, 0.80, 0.30, 0.16)
	(row["dim"] as ColorRect).visible = not it.is_ready()


func _update_log() -> void:
	if _log_text == null or _engine == null:
		return
	var events: Array = _engine.result().events
	# 事件数没变就不重排文本：每帧重设 text 会反复复位滚动位置，
	# 也会白白重排一次换行；只在真的追加了新事件时刷新。
	if events.size() == _log_event_count:
		return
	_log_event_count = events.size()
	if events.is_empty():
		_log_text.text = _EMPTY_LOG_HINT
		return
	# 从尾部往回取满 LOG_LINES 条「可显示」事件：use_item 是通用占位，
	# 与具体效果成对出现，日志里显示两遍只是挤占行数。
	var lines := PackedStringArray()
	var i := events.size() - 1
	while i >= 0 and lines.size() < LOG_LINES:
		var one := _format_event(events[i])
		if not one.is_empty():
			lines.append(one)
		i -= 1
	lines.reverse()
	_log_text.text = "\n".join(lines) if not lines.is_empty() else _EMPTY_LOG_HINT


func _format_event(raw: Variant) -> String:
	var ev: Dictionary = raw
	var step := int(ev.get("step", 0))
	var stamp := "%.1fs" % (float(step) * CombatEngine.STEP_SECONDS)
	var src: String = str(_item_names.get(str(ev.get("source", "")), ""))
	var who := "玩家" if int(ev.get("source_side", 0)) == CombatActor.SIDE_PLAYER else "敌方"
	# 文案按 191 像素宽的面板内腔裁剪过：一条尽量一行放下，
	# 否则中文会在行尾留单字（如「伤」/「害」各占一行），可读性明显变差。
	match String(ev.get("type", "")):
		"use_item":
			return ""
		"use_weapon":
			return "[%s] %s「%s」伤害 %.1f" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"use_shield":
			return "[%s] %s「%s」护盾 %.1f" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"heal":
			return "[%s] %s「%s」治疗 %.1f／实得 %.1f" % [stamp, who, src,
				float(ev.get("computed", 0.0)), float(ev.get("actual", 0.0))]
		"apply_burn":
			return "[%s] %s「%s」灼烧 %.1f 层" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"apply_poison":
			return "[%s] %s「%s」中毒 %.1f 层" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"apply_control":
			var detail: Dictionary = ev.get("detail", {})
			var victim := str(detail.get("target_item", ""))
			return "[%s] %s「%s」%s→%s %.1fs" % [stamp, who, src,
				_control_name(String(detail.get("control", ""))),
				str(_item_names.get(victim, victim)), float(ev.get("computed", 0.0)) / 1000.0]
		"storm":
			return "[%s] 沙尘暴 双方各受 %.1f（无视护盾）" % [stamp, float(ev.get("actual", 0.0))]
		"death":
			return "[%s] 战斗结束" % stamp
		_:
			return "[%s] %s「%s」" % [stamp, who, src]


func _control_name(control: String) -> String:
	match control:
		"haste":
			return "加速"
		"slow":
			return "减速"
		"freeze":
			return "冰冻"
	return control


# ---------------------------------------------------------------------------
# 布局自检
# ---------------------------------------------------------------------------

## 暴露实际排版结果，供无画面断言核对（与 PageMinimap.hero_indicator 同类）。
## 为什么要有它：组件面板与内腔来自生成器，界面层只是消费方；
## 只有把「实际摆到哪、多大」读出来，才能守住「格宽由净宽换算」「生命填充不出内腔」
## 这类只在真实渲染下才看得出来的约束。
func layout_report() -> Dictionary:
	var canvas := Vector2i.ZERO
	var canvas_min := Vector2i.ZERO
	if _canvas != null:
		canvas = Vector2i(_canvas.size)
		canvas_min = Vector2i(_canvas.custom_minimum_size)
	var sides := {}
	for view in [_enemy_side, _player_side]:
		var cells: Array = []
		for row in view.cells:
			var node := row["node"] as Control
			cells.append(Rect2i(node.position, node.size))
		var tray := Rect2i()
		if view.slots != null:
			tray = Rect2i(view.slots.position, view.slots.size)
		sides[view.key] = {
			"tray": tray,
			"slot_width": (float(tray.size.x) / float(SLOT_COUNT)) if tray.size.x > 0 else 0.0,
			"hp_inner": Rect2i(Vector2i(view.hp_inner.position), Vector2i(view.hp_inner.size)),
			"cells": cells,
		}
	var panels: Array = []
	for panel in BattleSkin.panel_names():
		if panel == BattleSkin.MODAL:
			continue
		var tex := BattleSkin.texture(panel)
		panels.append({
			"name": panel,
			"rect": BattleSkin.rect(panel),
			"inner": BattleSkin.inner(panel),
			"texture": Vector2i.ZERO if tex == null else Vector2i(tex.get_size()),
		})
	return {
		"canvas": canvas,
		"canvas_min": canvas_min,
		"design": BattleSkin.design_size(),
		"panels": panels,
		"sides": sides,
		"ops_bands": BattleSkin.bands_h(BattleSkin.OPERATIONS),
		"slot_count": SLOT_COUNT,
		"log": _log_report(),
	}


## 日志区的实际排版结果。单独暴露是因为它出过一个只在真实帧推进下才暴露的缺陷：
## 文本节点被外层容器压成 1 像素高，内容再全也看不见。
func _log_report() -> Dictionary:
	if _log_text == null:
		return {"rect": Rect2i(), "chars": 0, "lines": 0, "scroll_max": 0, "scroll_value": 0}
	return {
		"rect": Rect2i(Vector2i(_log_text.position), Vector2i(_log_text.size)),
		"chars": _log_text.get_total_character_count(),
		"lines": _log_text.get_line_count(),
		"scroll_max": int(_log_text.get_v_scroll_bar().max_value),
		"scroll_value": int(_log_text.get_v_scroll_bar().value),
	}
