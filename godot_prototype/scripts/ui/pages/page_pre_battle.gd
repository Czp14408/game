class_name PagePreBattle
extends PageBase
## 战前查看与调整：双方完整配置、机制信息与触发关系，以及调整／开始／取消。
## 边界：不给出胜率或必胜判断；页面只读配置并提交命令。
## 依据：游戏一阶段原型需求.md「战前机制信息」；技术方案第 6 节。

func build() -> void:
	var es := ctrl.encounter_state()
	var root := add_root("战前查看与调整")
	root.add_child(UiKit.label(hud(), 15, UiKit.COL_TEXT))
	if es == null:
		root.add_child(UiKit.label("遭遇不存在。", 16, UiKit.COL_ENEMY))
		root.add_child(UiKit.button("返回小地图", func() -> void: ctrl.cancel_battle()))
		return

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var player := ctrl.encounters.player_spec(ctrl.state)
	var enemy := ctrl.encounters.enemy_spec_from_encounter(ctrl.state, es)
	cols.add_child(_side_panel("我方配置", player, false))
	cols.add_child(_side_panel("对手配置%s" % ("（守路者）" if es.is_guard else ""), enemy, true))

	var actions := UiKit.panel("决策")
	actions.custom_minimum_size = Vector2(300, 0)
	cols.add_child(actions)
	var ab := UiKit.body(actions)
	ab.add_child(UiKit.label("保留对手完整配置查看与战前调整。", 14, UiKit.COL_MUTED))
	ab.add_child(UiKit.label("不给胜率或必胜判断，由你自行决定是否挑战。", 14, UiKit.COL_MUTED))
	ab.add_child(UiKit.spacer(8))
	if es.defeated:
		ab.add_child(UiKit.label("该对手已被击败，不会复活。", 15, UiKit.COL_MERCHANT))
		ab.add_child(UiKit.button("返回小地图", func() -> void: ctrl.cancel_battle()))
		return
	ab.add_child(UiKit.button("调整战斗栏与背包", func() -> void: ctrl.open_build(RunController.PAGE_PRE_BATTLE)))
	ab.add_child(UiKit.button("开始自动战斗", _on_start))
	ab.add_child(UiKit.button("取消（返回并屏蔽本次自动弹窗）", func() -> void: ctrl.cancel_battle()))
	if es.is_guard:
		ab.add_child(UiKit.spacer(6))
		ab.add_child(UiKit.label("守路者只锁定其守护通路，其他可选敌人不成为全图离开条件。", 13, UiKit.COL_MUTED))


func _on_start() -> void:
	var r := ctrl.confirm_battle()
	if not r.success:
		pass


func _side_panel(title: String, spec: Dictionary, is_enemy: bool) -> PanelContainer:
	var p := UiKit.panel(title)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := UiKit.body(p)
	if spec.is_empty():
		b.add_child(UiKit.label("配置缺失", 14, UiKit.COL_ENEMY))
		return p

	if is_enemy:
		b.add_child(UiKit.label("%s　生命 %.1f" % [
			spec.get("display_name", "对手"), float(spec.get("max_hp", 0.0)),
		], 15, UiKit.COL_ENEMY))
		var hints := _enemy_hints()
		if hints != "":
			b.add_child(UiKit.label(hints, 13, UiKit.COL_INTEL))
	else:
		b.add_child(UiKit.label("生命 %.1f / %.1f" % [
			float(spec.get("hp", 0.0)), float(spec.get("max_hp", 0.0)),
		], 15, UiKit.COL_PLAYER))
		var prof := catalog.trait_by_id(spec.get("profession", &""))
		var bl := catalog.trait_by_id(spec.get("bloodline", &""))
		b.add_child(UiKit.label("职业：%s（%s）" % [
			prof.display_name if prof != null else "无", prof.description if prof != null else "—",
		], 14, UiKit.COL_TEXT))
		b.add_child(UiKit.label("血统：%s（%s）" % [
			bl.display_name if bl != null else "无", bl.description if bl != null else "—",
		], 14, UiKit.COL_TEXT))

	var skills: Dictionary = spec.get("skills", {})
	b.add_child(UiKit.label("技能：%s" % (_skill_text(skills) if not skills.is_empty() else "无"), 14, UiKit.COL_TEXT))

	b.add_child(UiKit.spacer(6))
	b.add_child(UiKit.label("装备与机制（%d 件）" % (spec.get("items", []) as Array).size(), 15, UiKit.COL_ACCENT))
	var total := 0
	for raw in spec.get("items", []):
		var it: Dictionary = raw
		var def := catalog.item(it.get("definition_id", &""))
		if def == null:
			continue
		total += def.size
		var extra := ""
		if float(it.get("extra_value", 0.0)) != 0.0:
			extra = "　额外强化 +%.1f" % float(it.get("extra_value", 0.0))
		b.add_child(UiKit.label("· %s（%s）%d 格　CD %.1f 秒　%s%s" % [
			def.display_name, PriceTable.quality_name(int(it.get("quality", 0))), def.size,
			float(def.cooldown_ms) / 1000.0, UiKit.effect_text(def), extra,
		], 14, UiKit.COL_TEXT))
		var trig := UiKit.trigger_text(def)
		if trig != "":
			b.add_child(UiKit.label("　　%s" % trig, 13, UiKit.COL_MUTED))
	b.add_child(UiKit.label("合计占格：%d / 10" % total, 14, UiKit.COL_MUTED))
	b.add_child(UiKit.spacer(6))
	b.add_child(UiKit.label("释放链：使用武器 → 护身佩充能；使用护盾 → 越战越勇；治疗 → 回春护体。", 13, UiKit.COL_MUTED))
	b.add_child(UiKit.label("帧顺序：治疗／护盾先于伤害；新异常本步不跳伤；同帧同死判玩家失败。", 13, UiKit.COL_MUTED))
	return p


func _skill_text(skills: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in skills.keys():
		parts.append("%s（%s）" % [catalog.skill_display(k), PriceTable.quality_name(int(skills[k]))])
	return "、".join(parts)


## 已获得情报时给出对手战斗风格的定性提示（不揭示数值以外的结论）
func _enemy_hints() -> String:
	var state := ctrl.state
	var es := ctrl.encounter_state()
	if es == null:
		return ""
	if es.enemy_template_id == &"bandit_chief" and state.known_intel.has("chief_node"):
		return "已知情报：出手狠但间隔长（高伤害、长冷却）。"
	if es.enemy_template_id == &"mountain_guard" and state.node_state(es.node_id).guard_revealed.size() > 0:
		return "已知情报：守路者，击败后才能通过该连接。"
	return ""
