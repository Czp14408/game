class_name PageBattle
extends PageBase
## 自动战斗表现：固定步长推进、实时血条与冷却、事件日志与暂停菜单。
## 边界：只驱动 CombatEngine 与显示结果；结算通过 RunController 提交，本页不修改任何战斗数据。
## 依据：游戏可玩原型技术方案.md 第 7 节。

const LOG_LINES := 16


class SideView:
	var title: Label
	var hp_caption: Label
	var bar: Dictionary
	var status: Label
	var item_rows: Array = []


var _engine: CombatEngine
var _is_stage := false
var _acc := 0.0
var _rate := 1.0
var _paused := false
var _settled := false
var _step_label: Label
var _log_label: Label
var _log_scroll: ScrollContainer
var _pause_panel: PanelContainer
var _item_names: Dictionary = {}
var _player_view := SideView.new()
var _enemy_view := SideView.new()


func build() -> void:
	_is_stage = bool(payload.get("stage", false))
	_engine = ctrl.active_engine
	var root := add_root("自动战斗 · %s" % ("阶段试炼者" if _is_stage else "世界遭遇"))
	if _engine == null:
		root.add_child(UiKit.label("战斗引擎缺失，无法开始。", 16, UiKit.COL_ENEMY))
		root.add_child(UiKit.button("返回", func() -> void: ctrl.close_battle()))
		return

	for a in [_engine.player_actor(), _engine.enemy_actor()]:
		if a == null:
			continue
		for it in a.items:
			_item_names[it.instance_id] = it.display_name

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_build_side(_player_view, _engine.player_actor(), true))
	cols.add_child(_build_center())
	cols.add_child(_build_side(_enemy_view, _engine.enemy_actor(), false))

	_build_pause_panel()
	_refresh_view()
	set_process(true)


func _build_side(view: SideView, actor: CombatActor, is_player: bool) -> PanelContainer:
	var color := UiKit.COL_PLAYER if is_player else UiKit.COL_ENEMY
	var p := UiKit.panel(actor.display_name if actor != null else "？")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := UiKit.body(p)
	view.title = b.get_child(0) as Label
	view.bar = _make_bar(260, 20, color)
	b.add_child(view.bar["holder"])
	view.hp_caption = UiKit.label("", 14, UiKit.COL_TEXT)
	b.add_child(view.hp_caption)
	view.status = UiKit.label("", 13, UiKit.COL_MUTED)
	b.add_child(view.status)
	b.add_child(UiKit.spacer(6))
	b.add_child(UiKit.label("物品（释放次数／剩余冷却）", 14, UiKit.COL_ACCENT))
	if actor != null:
		for it in actor.items:
			var row := UiKit.vbox(0)
			var name_l := UiKit.label("· %s（%s）%d 格" % [
				it.display_name, PriceTable.quality_name(it.quality), it.size,
			], 14, UiKit.COL_TEXT)
			var detail_l := UiKit.label("", 13, UiKit.COL_MUTED)
			row.add_child(name_l)
			row.add_child(detail_l)
			b.add_child(row)
			view.item_rows.append({"name": name_l, "detail": detail_l, "item": it})
	return p


func _build_center() -> PanelContainer:
	var p := UiKit.panel("战斗进程")
	p.custom_minimum_size = Vector2(360, 0)
	var b := UiKit.body(p)
	_step_label = UiKit.label("", 15, UiKit.COL_TEXT)
	b.add_child(_step_label)
	var speed_row := UiKit.row(6)
	b.add_child(speed_row)
	speed_row.add_child(UiKit.button("×1", _set_rate.bind(1.0)))
	speed_row.add_child(UiKit.button("×2", _set_rate.bind(2.0)))
	speed_row.add_child(UiKit.button("×4", _set_rate.bind(4.0)))
	var ctrl_row := UiKit.row(6)
	b.add_child(ctrl_row)
	ctrl_row.add_child(UiKit.button("暂停／继续（Esc）", _toggle_pause))
	ctrl_row.add_child(UiKit.button("单步（F）", _single_step))
	ctrl_row.add_child(UiKit.button("瞬间算完", fast_forward))
	b.add_child(UiKit.label("事件日志（最近 %d 条）" % LOG_LINES, 14, UiKit.COL_ACCENT))
	_log_scroll = UiKit.scroll()
	_log_scroll.custom_minimum_size = Vector2(0, 220)
	_log_label = UiKit.label("", 13, UiKit.COL_MUTED)
	_log_scroll.add_child(_log_label)
	b.add_child(_log_scroll)
	return p


func _build_pause_panel() -> void:
	_pause_panel = UiKit.panel("战斗暂停")
	_pause_panel.visible = false
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause_panel.custom_minimum_size = Vector2(420, 0)
	var b := UiKit.body(_pause_panel)
	b.add_child(UiKit.label("暂停期间战斗时钟停止，不积累时间步。", 14, UiKit.COL_MUTED))
	b.add_child(UiKit.label("战斗中不能整理、交易、使用战斗外恢复品或中途退出到大地图。", 14, UiKit.COL_MUTED))
	b.add_child(UiKit.button("继续战斗（Esc）", _toggle_pause))
	b.add_child(UiKit.button("主动认输并结束试炼", _surrender))
	add_child(_pause_panel)


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


func _toggle_pause() -> void:
	_paused = not _paused
	if _pause_panel != null:
		_pause_panel.visible = _paused
	_refresh_view()


func _single_step() -> void:
	if _engine == null or _settled:
		return
	_paused = true
	if _pause_panel != null:
		_pause_panel.visible = true
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
	if _pause_panel != null:
		_pause_panel.visible = false
	if _is_stage:
		ctrl.settle_stage_battle(_engine)
	else:
		ctrl.settle_battle(_engine)


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

func _make_bar(width: int, height: int, color: Color) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, height)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2.ZERO
	fill.size = Vector2(width, height)
	holder.add_child(fill)
	return {"holder": holder, "fill": fill, "width": float(width), "height": float(height)}


func _refresh_view() -> void:
	if _engine == null:
		return
	_refresh_side(_player_view, _engine.player_actor())
	_refresh_side(_enemy_view, _engine.enemy_actor())
	var secs := float(_engine.current_step()) * CombatEngine.STEP_SECONDS
	_step_label.text = "已进行 %.1f 秒（第 %d 步）　播放倍速 ×%.0f　%s" % [
		secs, _engine.current_step(), _rate, "已暂停" if _paused else "进行中",
	]
	if secs >= 30.0:
		_step_label.text += "　⚠ 沙尘暴已开始（跳过护盾，伤害逐秒提高）"
	_update_log()


func _refresh_side(view: SideView, actor: CombatActor) -> void:
	if view == null or actor == null:
		return
	var ratio := clampf(actor.hp / maxf(actor.max_hp, 1.0), 0.0, 1.0)
	var fill: ColorRect = view.bar["fill"]
	fill.size = Vector2(float(view.bar["width"]) * ratio, float(view.bar["height"]))
	view.hp_caption.text = "生命 %.1f / %.1f　护盾 %.1f" % [maxf(actor.hp, 0.0), actor.max_hp, maxf(actor.shield, 0.0)]
	var parts := PackedStringArray()
	if actor.total_burn() > 0.0:
		parts.append("灼烧 %.1f" % actor.total_burn())
	if actor.total_poison() > 0.0:
		parts.append("中毒 %.1f（绕过护盾）" % actor.total_poison())
	if actor.weapon_damage_flat != 0.0:
		parts.append("武器固定加成 +%.1f" % actor.weapon_damage_flat)
	if actor.heal_on_weapon_use > 0.0:
		parts.append("使用武器吸血 %.1f" % actor.heal_on_weapon_use)
	if not actor.skills.is_empty():
		var sk := PackedStringArray()
		for k in actor.skills.keys():
			sk.append("%s（%s）" % [catalog.skill_display(k), PriceTable.quality_name(int(actor.skills[k]))])
		parts.append("技能：" + "、".join(sk))
	view.status.text = "　".join(parts) if parts.size() > 0 else "无附加状态"
	for row in view.item_rows:
		var it: BattleItemState = row["item"]
		var cd := it.cooldown_remaining_ms
		var ctrl_txt := PackedStringArray()
		if it.freeze_ms > 0:
			ctrl_txt.append("冰冻 %.1fs" % (float(it.freeze_ms) / 1000.0))
		if it.slow_ms > 0:
			ctrl_txt.append("减速 %.1fs" % (float(it.slow_ms) / 1000.0))
		if it.haste_ms > 0:
			ctrl_txt.append("加速 %.1fs" % (float(it.haste_ms) / 1000.0))
		var growth := ""
		if it.battle_growth != 0.0:
			growth = "　本场成长 +%.1f" % it.battle_growth
		(row["detail"] as Label).text = "　　释放 %d 次　剩余冷却 %.1fs / %.1fs%s%s" % [
			it.uses, float(maxi(cd, 0)) / 1000.0, float(it.base_cd_ms) / 1000.0,
			growth, ("　" + "　".join(ctrl_txt)) if ctrl_txt.size() > 0 else "",
		]


func _update_log() -> void:
	if _log_label == null or _engine == null:
		return
	var events: Array = _engine.result().events
	var start := maxi(events.size() - LOG_LINES, 0)
	var lines := PackedStringArray()
	for i in range(start, events.size()):
		lines.append(_format_event(events[i]))
	_log_label.text = "\n".join(lines)
	if _log_scroll != null:
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _format_event(raw: Variant) -> String:
	var ev: Dictionary = raw
	var step := int(ev.get("step", 0))
	var stamp := "%.1fs" % (float(step) * CombatEngine.STEP_SECONDS)
	var src: String = str(_item_names.get(str(ev.get("source", "")), ""))
	var who := "玩家" if int(ev.get("source_side", 0)) == CombatActor.SIDE_PLAYER else "敌方"
	match String(ev.get("type", "")):
		"use_weapon":
			return "[%s] %s「%s」造成 %.1f 伤害" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"use_shield":
			return "[%s] %s「%s」获得 %.1f 护盾" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"heal":
			return "[%s] %s「%s」治疗：计算 %.1f／实际 %.1f" % [stamp, who, src,
				float(ev.get("computed", 0.0)), float(ev.get("actual", 0.0))]
		"apply_burn":
			return "[%s] %s「%s」施加灼烧 %.1f 层" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"apply_poison":
			return "[%s] %s「%s」施加中毒 %.1f 层" % [stamp, who, src, float(ev.get("computed", 0.0))]
		"apply_control":
			var detail: Dictionary = ev.get("detail", {})
			return "[%s] %s 控制：%s → %s（%.1fs）" % [stamp, who,
				_control_name(String(detail.get("control", ""))), detail.get("target_item", ""),
				float(ev.get("computed", 0.0)) / 1000.0]
		"storm":
			return "[%s] 沙尘暴：双方各受 %.1f 伤害（忽略护盾与减伤）" % [stamp, float(ev.get("actual", 0.0))]
		"death":
			return "[%s] 战斗结束" % stamp
		_:
			return "[%s] %s 释放「%s」" % [stamp, who, src]


func _control_name(control: String) -> String:
	match control:
		"haste":
			return "加速"
		"slow":
			return "减速"
		"freeze":
			return "冰冻"
	return control
