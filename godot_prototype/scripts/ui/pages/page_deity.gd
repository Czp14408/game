class_name PageDeity
extends PageBase
## 主神整备：免费治疗、主神混合商店、构筑整理、阶段对手查看与挑战，以及认输。
## 依据：技术方案第 6、11 节；阶段对手在回归、进入整备时生成一次并保存。

var _hud_label: Label
var _heal_label: Label


func build() -> void:
	var root := add_root("主神空间 · 整备")
	_hud_label = UiKit.label(hud(), 15, UiKit.COL_TEXT)
	root.add_child(_hud_label)

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel("整备操作")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lb := UiKit.body(left)
	lb.add_child(UiKit.label("主线已完成、已回归主神空间，武道世界不可再进入。此处可交易、合成与恢复。", 14, UiKit.COL_MUTED))
	lb.add_child(UiKit.spacer(6))
	_heal_label = UiKit.label("", 15, UiKit.COL_TEXT)
	lb.add_child(_heal_label)
	lb.add_child(UiKit.label("主神治疗免费、直接回满，不消耗恢复品，也不恢复战败次数。", 13, UiKit.COL_MUTED))
	lb.add_child(UiKit.button("免费治疗（回满生命）", _on_heal))
	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.button("主神混合商店", func() -> void: ctrl.open_shop("deity/deity_mixed", RunController.PAGE_DEITY)))
	lb.add_child(UiKit.button("构筑与整理", func() -> void: ctrl.open_build(RunController.PAGE_DEITY)))
	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.label("阶段挑战", 16, UiKit.COL_ACCENT))
	lb.add_child(UiKit.label("阶段对手在回归时生成一次并固定，不因换装或重试改变。", 13, UiKit.COL_MUTED))
	lb.add_child(UiKit.button("查看阶段对手并挑战", func() -> void: ctrl.open_stage_preview()))
	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.button("主动认输（结束试炼）", func() -> void: ctrl.surrender()))

	var right := UiKit.panel("当前状态")
	right.custom_minimum_size = Vector2(380, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	var state := ctrl.state
	var opp: Dictionary = state.stage_opponent
	rb.add_child(UiKit.label("生命 %.1f / %.1f　货币 %d" % [state.current_hp, state.max_hp, state.money], 15, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("累计战败 %d / %d" % [state.defeats, RunState.MAX_DEFEATS], 15, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("战斗栏占用 %d / %d　背包占用 %d / %d" % [
		state.bar_used(), RunState.BAR_CAPACITY, state.inventory_used(), RunState.INVENTORY_CAPACITY,
	], 14, UiKit.COL_MUTED))
	rb.add_child(UiKit.spacer(6))
	if opp.is_empty():
		rb.add_child(UiKit.label("阶段对手尚未生成。", 14, UiKit.COL_MUTED))
	else:
		rb.add_child(UiKit.label("阶段对手：%s　生命 %.1f" % [opp.get("display_name", "?"), float(opp.get("max_hp", 0.0))], 15, UiKit.COL_ENEMY))
		for g in opp.get("equipment", []):
			var grant := g as GrantDef
			if grant == null:
				continue
			rb.add_child(UiKit.label("· %s（%s）" % [catalog.item_display(grant.definition_id), PriceTable.quality_name(grant.quality)], 14, UiKit.COL_TEXT))
	rb.add_child(UiKit.spacer(6))
	rb.add_child(UiKit.label("阶段 Boss 无实物掉落、不发货币；阶段胜利即原型阶段完成。", 13, UiKit.COL_MUTED))
	rb.add_child(UiKit.spacer(8))
	rb.add_child(UiKit.label("任务与情报", 16, UiKit.COL_ACCENT))
	var w := ctrl.world.world(state)
	if w != null:
		for qdef in w.quests:
			var qs := state.quest_state(qdef.quest_id)
			rb.add_child(UiKit.label("%s：%s" % [qdef.display_name, String(qs.status)], 14, UiKit.COL_MUTED))

	_refresh()


func _on_heal() -> void:
	var r := ctrl.deity_heal()
	if r.success:
		_refresh()
	else:
		_heal_label.text = "生命已满，无需治疗。"


func _refresh() -> void:
	if _hud_label != null:
		_hud_label.text = hud()
	if _heal_label != null:
		var state := ctrl.state
		_heal_label.text = "当前生命 %.1f / %.1f" % [state.current_hp, state.max_hp]
