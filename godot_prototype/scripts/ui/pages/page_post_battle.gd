class_name PagePostBattle
extends PageBase
## 战后反馈：胜负、耗时、剩余生命、各物品释放次数／伤害／护盾／实际治疗量，
## 以及掉落、技能当场决策与待拾取实物。
## 依据：游戏一阶段原型需求.md「战后反馈」；技术方案第 13 节。

var _dynamic: VBoxContainer


func build() -> void:
	var root := add_root("战后反馈")
	root.add_child(UiKit.label(hud(), 15, UiKit.COL_TEXT))

	var result := ctrl.last_result
	var summary: Dictionary = payload.get("summary", ctrl.last_battle_summary)
	if result == null:
		root.add_child(UiKit.label("没有可显示的结算结果。", 16, UiKit.COL_MUTED))
		root.add_child(UiKit.button("继续探索", func() -> void: ctrl.leave_post_battle()))
		return

	var head := UiKit.panel("本场结果")
	root.add_child(head)
	var hb := UiKit.body(head)
	var win := result.winner_is_player()
	var outcome_col := UiKit.COL_MERCHANT if win else UiKit.COL_ENEMY
	hb.add_child(UiKit.label("结果：%s　耗时：%s" % [result.outcome_text(), result.duration_text()], 18, outcome_col))
	hb.add_child(UiKit.label("我方剩余生命 %.1f / %.1f（护盾 %.1f）　对手：%s 剩余 %.1f / %.1f" % [
		result.player_hp, result.player_max_hp, result.player_shield,
		result.enemy_name, result.enemy_hp, result.enemy_max_hp,
	], 15, UiKit.COL_TEXT))
	if result.same_step_death:
		hb.add_child(UiKit.label("同帧同死：按规则判玩家失败。", 14, UiKit.COL_ENEMY))
	if not win:
		hb.add_child(UiKit.label("战败：失败遭遇不磨损对手、不重置商店，可回到战前状态重试；当前战败 %d / %d。" % [
			ctrl.state.defeats, RunState.MAX_DEFEATS,
		], 14, UiKit.COL_ENEMY))

	var cols := UiKit.row(12)
	root.add_child(cols)
	cols.add_child(_stats_panel("我方物品统计", result.item_stats.get("player", []), result.player_stats))
	cols.add_child(_stats_panel("对手物品统计", result.item_stats.get("enemy", []), result.enemy_stats))

	# 掉落、技能决策与拾取区内容可能较长，放进滚动区避免被窗口底部裁掉
	_dynamic = UiKit.vbox(6)
	root.add_child(UiKit.scroll_into(_dynamic))
	_refresh()


func _stats_panel(title: String, rows: Array, actor_stats: Dictionary) -> PanelContainer:
	var p := UiKit.panel(title)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := UiKit.body(p)
	if rows.is_empty():
		b.add_child(UiKit.label("本场没有物品参与。", 14, UiKit.COL_MUTED))
	for raw in rows:
		var s: Dictionary = raw
		b.add_child(UiKit.label("· %s（%s）释放 %d 次" % [
			s.get("display_name", "?"), PriceTable.quality_name(int(s.get("quality", 0))), int(s.get("uses", 0)),
		], 15, UiKit.COL_TEXT))
		b.add_child(UiKit.label("　　伤害 %.1f（攻击 %.1f／灼烧 %.1f／中毒 %.1f）　护盾 %.1f　治疗 实际 %.1f／计算 %.1f" % [
			float(s.get("damage_total", 0.0)), float(s.get("damage_attack", 0.0)),
			float(s.get("damage_burn", 0.0)), float(s.get("damage_poison", 0.0)),
			float(s.get("shield_gained", 0.0)), float(s.get("heal_actual", 0.0)),
			float(s.get("heal_computed", 0.0)),
		], 13, UiKit.COL_MUTED))
	b.add_child(UiKit.spacer(4))
	b.add_child(UiKit.label("汇总：护盾获得 %.1f　实际治疗 %.1f　承受护盾伤害 %.1f　承受生命伤害 %.1f　沙尘暴 %.1f" % [
		float(actor_stats.get("shield_gained", 0.0)), float(actor_stats.get("heal_actual", 0.0)),
		float(actor_stats.get("damage_taken_shield", 0.0)), float(actor_stats.get("damage_taken_hp", 0.0)),
		float(actor_stats.get("storm_damage", 0.0)),
	], 13, UiKit.COL_MUTED))
	var extra := _non_item_stats(actor_stats)
	if extra != "":
		b.add_child(UiKit.label("非物品来源（职业／血统／技能）：%s" % extra, 13, UiKit.COL_MUTED))
	return p


func _non_item_stats(actor_stats: Dictionary) -> String:
	var parts := PackedStringArray()
	var traits: Dictionary = actor_stats.get("trait_stats", {})
	for k in traits.keys():
		parts.append("%s %.1f" % [k, float(traits[k])])
	var skills: Dictionary = actor_stats.get("skill_stats", {})
	for k in skills.keys():
		parts.append("%s %.1f" % [catalog.skill_display(StringName(k)), float(skills[k])])
	return "、".join(parts)


func _refresh() -> void:
	if _dynamic == null:
		return
	for c in _dynamic.get_children():
		_dynamic.remove_child(c)
		c.queue_free()
	var summary: Dictionary = payload.get("summary", ctrl.last_battle_summary)
	var es := ctrl.encounter_state()

	var rewards := UiKit.panel("结算与掉落")
	_dynamic.add_child(rewards)
	var rb := UiKit.body(rewards)
	rb.add_child(UiKit.label("货币变化：+%d（现有 %d）" % [int(summary.get("money_gain", 0)), ctrl.state.money], 15, UiKit.COL_TEXT))
	var drops: Array = summary.get("drops", [])
	if drops.is_empty():
		rb.add_child(UiKit.label("本场没有实物掉落。", 14, UiKit.COL_MUTED))
	for raw in drops:
		var d: Dictionary = raw
		if String(d.get("kind", "")) == "skill":
			rb.add_child(UiKit.label("掉落技能：%s（%s）" % [
				catalog.skill_display(StringName(d.get("definition_id", ""))),
				PriceTable.quality_name(int(d.get("quality", 0))),
			], 14, UiKit.COL_ACCENT))
		elif String(d.get("kind", "")) == "material":
			rb.add_child(UiKit.label("掉落材料：%s" % catalog.item_display(&"scrap_material"), 14, UiKit.COL_TEXT))
		else:
			rb.add_child(UiKit.label("掉落物品：%s（%s）" % [
				catalog.item_display(StringName(d.get("definition_id", ""))),
				PriceTable.quality_name(int(d.get("quality", 0))),
			], 14, UiKit.COL_TEXT))
	var quests: Array = summary.get("quests", [])
	for raw in quests:
		var q: Dictionary = raw
		if q.has("display_name"):
			rb.add_child(UiKit.label("任务完成：%s" % q["display_name"], 14, UiKit.COL_INTEL))
		if q.has("auto_claimed"):
			rb.add_child(UiKit.label("　自动入账任务奖励 %d" % int(q.get("money", 0)), 13, UiKit.COL_INTEL))

	var must_decide := false
	if es != null:
		if not es.pending_skill.is_empty():
			must_decide = true
			var sp := UiKit.panel("技能掉落必须当场决策")
			_dynamic.add_child(sp)
			var sb := UiKit.body(sp)
			sb.add_child(UiKit.label("获得技能：%s（%s）。学习或放弃，放弃后不能再通过重访重新领取。" % [
				catalog.skill_display(es.pending_skill["skill_id"]),
				PriceTable.quality_name(int(es.pending_skill["quality"])),
			], 15, UiKit.COL_ACCENT))
			var row := UiKit.row(8)
			sb.add_child(row)
			row.add_child(UiKit.button("学习该技能", _on_learn))
			row.add_child(UiKit.button("放弃", _on_decline))
		if not es.pending_drops.is_empty():
			var dp := UiKit.panel("待拾取实物（容量不足时留在原地）")
			_dynamic.add_child(dp)
			var db := UiKit.body(dp)
			db.add_child(UiKit.label("背包占用 %d / %d　战斗栏占用 %d / %d" % [
				ctrl.state.inventory_used(), RunState.INVENTORY_CAPACITY,
				ctrl.state.bar_used(), RunState.BAR_CAPACITY,
			], 14, UiKit.COL_MUTED))
			for it in es.pending_drops:
				db.add_child(UiKit.label("· %s" % item_line(it), 14, UiKit.COL_TEXT))
			var drow := UiKit.row(8)
			db.add_child(drow)
			drow.add_child(UiKit.button("全部拾取", _on_pickup))
			drow.add_child(UiKit.button("整理背包（构筑）", func() -> void: ctrl.open_build(RunController.PAGE_POST_BATTLE)))

	var footer := UiKit.row(8)
	_dynamic.add_child(footer)
	var leave := UiKit.button("继续探索", func() -> void: ctrl.leave_post_battle(), must_decide)
	footer.add_child(leave)
	footer.add_child(UiKit.button("构筑与整理", func() -> void: ctrl.open_build(RunController.PAGE_POST_BATTLE)))
	if must_decide:
		_dynamic.add_child(UiKit.label("需先决定技能掉落的取舍，才能离开战后界面。", 13, UiKit.COL_ENEMY))
	_dynamic.add_child(UiKit.label("提示：中毒绕过护盾；护身佩在使用武器时被充能 1 秒；满血治疗仍产生治疗事件。", 13, UiKit.COL_MUTED))


func _on_learn() -> void:
	ctrl.resolve_skill_drop(true)
	_refresh()


func _on_decline() -> void:
	ctrl.resolve_skill_drop(false)
	_refresh()


func _on_pickup() -> void:
	ctrl.pickup_drops()
	_refresh()
