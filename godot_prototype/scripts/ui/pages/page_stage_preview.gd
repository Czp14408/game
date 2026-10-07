class_name PageStagePreview
extends PageBase
## 阶段战前查看：展示已固定的阶段对手（模板 + 追加组件），可调整后挑战。
## 依据：技术方案第 6 节；九种配置 = 3 模板 × 3 追加组件，生成后固定。

func build() -> void:
	var opp: Dictionary = payload.get("opponent", ctrl.state.stage_opponent)
	var root := add_root("阶段战前查看")
	root.add_child(UiKit.label(hud(), 15, UiKit.COL_TEXT))

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel("阶段对手配置")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lb := UiKit.body(left)
	if opp.is_empty():
		lb.add_child(UiKit.label("阶段对手尚未生成。", 16, UiKit.COL_ENEMY))
	else:
		lb.add_child(UiKit.label("%s" % opp.get("display_name", "?"), 18, UiKit.COL_ENEMY))
		lb.add_child(UiKit.label("生命 %.1f　占格合计 %d / 10" % [float(opp.get("max_hp", 0.0)), _total_size(opp)], 15, UiKit.COL_TEXT))
		lb.add_child(UiKit.spacer(6))
		lb.add_child(UiKit.label("装备与机制", 15, UiKit.COL_ACCENT))
		for g in opp.get("equipment", []):
			var grant := g as GrantDef
			if grant == null:
				continue
			var def := catalog.item(grant.definition_id)
			if def == null:
				continue
			lb.add_child(UiKit.label("· %s（%s）%d 格　CD %.1f 秒　%s" % [
				def.display_name, PriceTable.quality_name(grant.quality), def.size,
				float(def.cooldown_ms) / 1000.0, UiKit.effect_text(def),
			], 14, UiKit.COL_TEXT))
			var trig := UiKit.trigger_text(def)
			if trig != "":
				lb.add_child(UiKit.label("　　%s" % trig, 13, UiKit.COL_MUTED))
		lb.add_child(UiKit.spacer(6))
		lb.add_child(UiKit.label("阶段对手不附加职业、血统或独立技能；配置在回归时固定，换装与重试都不改变它。", 13, UiKit.COL_MUTED))
		lb.add_child(UiKit.label("阶段 Boss 无实物掉落、不发货币，成功即代表原型阶段完成。", 13, UiKit.COL_MUTED))

	var right := UiKit.panel("决策")
	right.custom_minimum_size = Vector2(320, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	rb.add_child(UiKit.label("我方：生命 %.1f / %.1f　战斗栏 %d / %d 格" % [
		ctrl.state.current_hp, ctrl.state.max_hp, ctrl.state.bar_used(), RunState.BAR_CAPACITY,
	], 15, UiKit.COL_PLAYER))
	rb.add_child(UiKit.spacer(8))
	rb.add_child(UiKit.button("调整战斗栏与背包", func() -> void: ctrl.open_build(RunController.PAGE_STAGE_PREVIEW)))
	rb.add_child(UiKit.button("开始阶段战斗", _on_start))
	rb.add_child(UiKit.button("返回主神整备", func() -> void: ctrl.cancel_stage_preview()))


func _on_start() -> void:
	if ctrl.state.stage_opponent.is_empty():
		return
	ctrl.confirm_stage_battle()


func _total_size(opp: Dictionary) -> int:
	var total := 0
	for g in opp.get("equipment", []):
		var grant := g as GrantDef
		if grant == null:
			continue
		var def := catalog.item(grant.definition_id)
		if def != null:
			total += def.size
	return total
