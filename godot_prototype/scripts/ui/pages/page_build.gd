class_name PageBuild
extends PageBase
## 构筑与整理：战斗栏／背包的装备、卸下、合成、使用恢复品与丢弃，技能与职业血统展示。
## 采用「选择物品→按钮」方式，不要求拖拽。
## 依据：技术方案第 11 节。

var _bar_box: VBoxContainer
var _inv_box: VBoxContainer
var _hud_label: Label
var _note: Label


func build() -> void:
	var root := add_root("构筑与整理")
	_hud_label = UiKit.label(hud(), 15, UiKit.COL_TEXT)
	root.add_child(_hud_label)
	_note = UiKit.label("", 14, UiKit.COL_ACCENT)
	root.add_child(_note)

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel("战斗栏（按大小占 10 格）")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_bar_box = UiKit.vbox(6)
	UiKit.body(left).add_child(_bar_box)

	var mid := UiKit.panel("背包（10 点容量，不堆叠）")
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mid)
	_inv_box = UiKit.vbox(6)
	UiKit.body(mid).add_child(_inv_box)

	var right := UiKit.panel("技能、职业与血统")
	right.custom_minimum_size = Vector2(320, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	var prof := catalog.trait_by_id(ctrl.state.profession)
	var bl := catalog.trait_by_id(ctrl.state.bloodline)
	rb.add_child(UiKit.label("职业：%s" % (prof.display_name if prof != null else "无"), 15, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("　%s" % (prof.description if prof != null else ""), 13, UiKit.COL_MUTED))
	rb.add_child(UiKit.label("血统：%s" % (bl.display_name if bl != null else "无"), 15, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("　%s" % (bl.description if bl != null else ""), 13, UiKit.COL_MUTED))
	rb.add_child(UiKit.spacer(6))
	rb.add_child(UiKit.label("已学技能（全部生效、无数量上限）", 15, UiKit.COL_ACCENT))
	if ctrl.state.skills.is_empty():
		rb.add_child(UiKit.label("尚未学会技能。", 14, UiKit.COL_MUTED))
	for k in ctrl.state.skills.keys():
		var ss: SkillState = ctrl.state.skills[k]
		var sd := catalog.skill(k)
		rb.add_child(UiKit.label("· %s（%s）" % [catalog.skill_display(k), PriceTable.quality_name(ss.quality)], 14, UiKit.COL_TEXT))
		if sd != null:
			rb.add_child(UiKit.label("　　触发「%s」→ %s %.1f" % [sd.trigger_event, sd.effect_type, sd.value_at(ss.quality)], 13, UiKit.COL_MUTED))
	rb.add_child(UiKit.spacer(10))
	rb.add_child(UiKit.button("返回", func() -> void: ctrl.close_build()))

	_refresh()


func _refresh() -> void:
	if _hud_label != null:
		_hud_label.text = hud()
	var state := ctrl.state
	if _bar_box != null:
		for c in _bar_box.get_children():
			_bar_box.remove_child(c)
			c.queue_free()
		_bar_box.add_child(UiKit.label("已占用 %d / %d 格（小 1／中 2／大 3）" % [state.bar_used(), RunState.BAR_CAPACITY], 14, UiKit.COL_MUTED))
		if state.battle_bar.is_empty():
			_bar_box.add_child(UiKit.label("战斗栏为空：战斗中将没有可释放的物品。", 14, UiKit.COL_ENEMY))
		for it in state.battle_bar:
			_bar_box.add_child(_item_row(it, "bar"))
	if _inv_box != null:
		for c in _inv_box.get_children():
			_inv_box.remove_child(c)
			c.queue_free()
		_inv_box.add_child(UiKit.label("已占用 %d / %d 点" % [state.inventory_used(), RunState.INVENTORY_CAPACITY], 14, UiKit.COL_MUTED))
		if state.inventory.is_empty():
			_inv_box.add_child(UiKit.label("背包为空。", 14, UiKit.COL_MUTED))
		for it in state.inventory:
			_inv_box.add_child(_item_row(it, "inv"))
	if _note != null:
		_note.text = "容量校验按操作后的总占用计算；失败不移动半件物品、不扣币不丢物。"


func _item_row(it: ItemInstance, where: String) -> VBoxContainer:
	var box := UiKit.vbox(2)
	var def := catalog.item(it.definition_id)
	box.add_child(UiKit.label(item_line(it), 15, UiKit.COL_TEXT))
	if def != null:
		box.add_child(UiKit.label("　　%d 格　CD %.1f 秒　%s" % [def.size, float(def.cooldown_ms) / 1000.0, UiKit.effect_text(def)], 13, UiKit.COL_MUTED))
	var row := UiKit.row(6)
	box.add_child(row)
	if where == "bar":
		row.add_child(UiKit.button("卸下", func() -> void: _do(ctrl.unequip(it.instance_id))))
	else:
		if def != null and def.equippable:
			row.add_child(UiKit.button("装备", func() -> void: _do(ctrl.equip(it.instance_id))))
		if def != null and def.category == ItemDef.CAT_CONSUMABLE:
			var can_use := ctrl.state.current_hp < ctrl.state.max_hp
			row.add_child(UiKit.button("使用（恢复 %d）" % int(def.out_of_combat_heal), func() -> void: _do(ctrl.use_recovery(it.instance_id)), not can_use))
	var candidates := ctrl.inventory.synthesis_candidates(ctrl.state, it.instance_id)
	if not candidates.is_empty():
		row.add_child(UiKit.button("合成", func() -> void: _do(ctrl.synthesize(it.instance_id, candidates[0]), true)))
	row.add_child(UiKit.button("丢弃", func() -> void: _do(ctrl.discard_item(it.instance_id))))
	return box


func _do(_result: OperationResult, _refresh_hint: bool = false) -> void:
	_refresh()
