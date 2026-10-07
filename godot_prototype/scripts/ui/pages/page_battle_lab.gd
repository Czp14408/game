class_name PageBattleLab
extends PageBase
## 战斗实验室：选双方配置、生命、种子，单步或快速计算并展示统计。
## 依据：技术方案第 14 节「开发入口」。
##
## 边界：只在开发菜单出现；不写入试炼状态，不影响正常游玩数值。

const PRESETS := [
	{"name": "空手", "items": []},
	{"name": "青铜长刀", "items": ["long_blade"]},
	{"name": "长刀＋护身佩", "items": ["long_blade", "ward_charm"]},
	{"name": "长刀＋短刃＋护身佩", "items": ["long_blade", "short_blade", "ward_charm"]},
	{"name": "长刀＋重盾＋回春＋火油＋毒针", "items": ["long_blade", "tower_shield", "rejuvenator", "fire_oil", "poison_needle"]},
	{"name": "长刀＋加速＋减速＋冰冻", "items": ["long_blade", "stimulator", "leg_binder", "frost_seal"]},
	{"name": "长刀＋重锤", "items": ["long_blade", "heavy_hammer"]},
	{"name": "土匪短刀＋护身佩", "items": ["bandit_knife", "ward_charm"]},
]

var _engine: CombatEngine = null
var _rng: RandomService
var _preset_picker: OptionButton
var _enemy_picker: OptionButton
var _hp_box: SpinBox
var _seed_box: LineEdit
var _result_box: VBoxContainer
var _log_label: RichTextLabel
var _status: Label
var _enemy_ids: Array[StringName] = []


func build() -> void:
	var root := add_root("战斗实验室")
	root.add_child(UiKit.label("开发测试入口：只改变本次会话的显式计算输入，不修改正式规则与数值。", 14, UiKit.COL_MUTED))
	root.add_child(UiKit.label("职业与血统不参与（对比“无职业血统”基准），对手使用其定义中的装备与技能。", 14, UiKit.COL_MUTED))

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel("输入")
	left.custom_minimum_size = Vector2(380, 0)
	cols.add_child(left)
	var lb := UiKit.body(left)
	lb.add_child(UiKit.label("我方配置", 15, UiKit.COL_ACCENT))
	_preset_picker = OptionButton.new()
	for p in PRESETS:
		_preset_picker.add_item(String(p["name"]))
	lb.add_child(_preset_picker)

	lb.add_child(UiKit.label("对手", 15, UiKit.COL_ACCENT))
	_enemy_picker = OptionButton.new()
	for id in catalog.enemies.keys():
		_enemy_ids.append(id)
		var def := catalog.enemy(id)
		_enemy_picker.add_item("%s（生命 %.0f）" % [def.display_name, def.max_hp])
	lb.add_child(_enemy_picker)

	lb.add_child(UiKit.label("我方生命上限（默认 100，与血统修正无关）", 15, UiKit.COL_ACCENT))
	_hp_box = SpinBox.new()
	_hp_box.min_value = 1
	_hp_box.max_value = 999
	_hp_box.step = 1
	_hp_box.value = RunState.BASE_MAX_HP
	lb.add_child(_hp_box)

	lb.add_child(UiKit.label("随机种子（战斗内控制目标抽取）", 15, UiKit.COL_ACCENT))
	_seed_box = LineEdit.new()
	_seed_box.text = "20261007"
	lb.add_child(_seed_box)

	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.button("重置并准备", _reset_engine))
	lb.add_child(UiKit.button("单步（1 个时间步）", _single_step))
	lb.add_child(UiKit.button("快速计算（跑完全场）", _run_all))
	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.button("返回开局选择", func() -> void: ctrl.start_new_app()))

	var right := UiKit.panel("输出")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rb := UiKit.body(right)
	_status = UiKit.label("", 15, UiKit.COL_TEXT)
	rb.add_child(_status)
	_result_box = UiKit.vbox(4)
	rb.add_child(_result_box)
	rb.add_child(UiKit.label("事件日志", 15, UiKit.COL_ACCENT))
	# 用自带滚动的 RichTextLabel：Label 开自动换行后被 ScrollContainer 压成 1 像素高，
	# 整块日志区看不见内容（与战斗页同因，见 ui_kit.gd 的 log_text）。
	_log_label = UiKit.log_text(13, UiKit.COL_MUTED)
	_log_label.custom_minimum_size = Vector2(0, 200)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rb.add_child(_log_label)

	_reset_engine()


# ---------------------------------------------------------------------------

func _player_spec() -> Dictionary:
	var idx := _preset_picker.selected
	var preset: Dictionary = PRESETS[clampi(idx, 0, PRESETS.size() - 1)]
	var items := []
	for id in preset["items"]:
		items.append({"definition_id": StringName(id), "quality": 0})
	return {
		"side": CombatActor.SIDE_PLAYER,
		"display_name": "测试方",
		"max_hp": float(_hp_box.value),
		"hp": float(_hp_box.value),
		"items": items,
	}


func _reset_engine() -> void:
	var seed_value := int(_seed_box.text) if _seed_box.text.is_valid_int() else 20261007
	_rng = RandomService.create(seed_value)
	var player := CombatEngine.build_actor(catalog, _player_spec())
	var eid: StringName = _enemy_ids[clampi(_enemy_picker.selected, 0, _enemy_ids.size() - 1)]
	var enemy := CombatEngine.build_enemy(catalog, catalog.enemy(eid))
	_engine = CombatEngine.new()
	_engine.catalog = catalog
	_engine.rng = _rng
	_engine.begin(player, enemy, "lab", "lab/%d" % seed_value)
	_status.text = "对手：%s　种子 %d　第 0 步" % [enemy.display_name, seed_value]
	_render()


func _single_step() -> void:
	if _engine == null:
		return
	_engine.step()
	_render()


func _run_all() -> void:
	if _engine == null:
		return
	_engine.run_all()
	_render()


func _render() -> void:
	if _engine == null or _result_box == null:
		return
	var r := _engine.result()
	var p := _engine.player_actor()
	var e := _engine.enemy_actor()
	for c in _result_box.get_children():
		_result_box.remove_child(c)
		c.queue_free()
	_status.text = "第 %d 步（%.1f 秒）　%s" % [
		_engine.current_step(), float(_engine.current_step()) * CombatEngine.STEP_SECONDS,
		"已结束" if _engine.is_finished() else "进行中",
	]
	_result_box.add_child(UiKit.label("我方生命 %.1f / %.1f（护盾 %.1f）" % [maxf(p.hp, 0.0), p.max_hp, maxf(p.shield, 0.0)], 15, UiKit.COL_PLAYER))
	_result_box.add_child(UiKit.label("对手生命 %.1f / %.1f（护盾 %.1f）" % [maxf(e.hp, 0.0), e.max_hp, maxf(e.shield, 0.0)], 15, UiKit.COL_ENEMY))
	if _engine.is_finished():
		_result_box.add_child(UiKit.label("结果：%s　耗时 %s" % [r.outcome_text(), r.duration_text()], 16, UiKit.COL_ACCENT))
		for raw in r.item_stats.get("player", []):
			var s: Dictionary = raw
			_result_box.add_child(UiKit.label("我方「%s」释放 %d 次　伤害 %.1f　护盾 %.1f　治疗 实际 %.1f" % [
				s.get("display_name", "?"), int(s.get("uses", 0)), float(s.get("damage_total", 0.0)),
				float(s.get("shield_gained", 0.0)), float(s.get("heal_actual", 0.0)),
			], 14, UiKit.COL_TEXT))
		for raw in r.item_stats.get("enemy", []):
			var s2: Dictionary = raw
			_result_box.add_child(UiKit.label("敌方「%s」释放 %d 次　伤害 %.1f　护盾 %.1f　治疗 实际 %.1f" % [
				s2.get("display_name", "?"), int(s2.get("uses", 0)), float(s2.get("damage_total", 0.0)),
				float(s2.get("shield_gained", 0.0)), float(s2.get("heal_actual", 0.0)),
			], 14, UiKit.COL_MUTED))
	var events: Array = r.events
	var start := maxi(events.size() - 20, 0)
	var lines := PackedStringArray()
	for i in range(start, events.size()):
		var ev: Dictionary = events[i]
		lines.append("[%.1fs] %s %s 计算 %.1f／实际 %.1f" % [
			float(int(ev.get("step", 0))) * CombatEngine.STEP_SECONDS,
			ev.get("type", ""), ev.get("source", ""),
			float(ev.get("computed", 0.0)), float(ev.get("actual", 0.0)),
		])
	_log_label.text = "\n".join(lines)
