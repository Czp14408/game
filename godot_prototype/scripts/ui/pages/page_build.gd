class_name PageBuild
extends PageBase
## 构筑与整理：右侧「背包／商店／整理共用面板」的整理模式——上排战斗栏、下排背包。
## 采用「点物品 → 底部操作条给可用操作」方式，不要求拖拽。
## 依据：技术方案第 11 节；背包商店整理共用面板说明.md；ui修改迭代工作流.md。
##
## 布局：设计画布 1280×690（1280×720 逻辑画布减去顶部 30 像素状态条）。
## 面板矩形与三段分区全部来自 InventorySkin（生成器产出），本页不写死面板坐标；
## 左侧文字区是本页自己的版面，坐标写在这里，不涉及组件对齐。

## 左侧信息列（设计坐标，本页自己的版面）
const LEFT_X := 16
const LEFT_W := 620
const Y_TITLE := 12
const Y_NOTE := 46
const Y_ROWS := 72
const Y_TRAIT := 122
const Y_SKILLS_HEAD := 186
const Y_SKILLS := 208
const H_SKILLS := 148
const Y_DETAIL_HEAD := 368
const Y_DETAIL := 390
const H_DETAIL := 112
const Y_LEGEND := 512

var _canvas: Control
var _panel: PanelInventory
var _note: Label
var _rows_label: Label
var _traits: Label
var _skills: RichTextLabel
var _detail_head: Label
var _detail: Label

var _sel_id := ""       ## 形如 "bar:<instance_id>" / "inv:<instance_id>"
var _sel_row := ""
var _sel_instance := ""


func build() -> void:
	# 页面区第一层必须是铺满宽度的容器：真渲染布局断言据此判断页面没被压窄。
	var center := CenterContainer.new()
	center.name = "BuildCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_canvas_setup(center)

	if ctrl == null or ctrl.state == null:
		_canvas.add_child(UiKit.abs_label("尚未开始试炼。", 16, UiKit.COL_ENEMY, Rect2i(40, 40, 600, 30)))
		return

	_build_left()
	_build_panel()
	_refresh()


func _canvas_setup(center: CenterContainer) -> void:
	_canvas = Control.new()
	_canvas.name = "DesignCanvas"
	var design := InventorySkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_canvas.custom_minimum_size = Vector2(design)
	center.add_child(_canvas)
	_canvas.add_child(UiKit.solid(UiKit.COL_BG, Rect2i(Vector2i.ZERO, design)))


func _build_left() -> void:
	_canvas.add_child(UiKit.abs_label("构筑与整理", 20, UiKit.COL_ACCENT,
		Rect2i(LEFT_X, Y_TITLE, LEFT_W, 28)))
	_note = UiKit.abs_block("", 13, UiKit.COL_ACCENT, Rect2i(LEFT_X, Y_NOTE, LEFT_W, 22))
	_note.name = "BuildNote"
	_canvas.add_child(_note)

	_rows_label = UiKit.abs_block("", 13, UiKit.COL_TEXT, Rect2i(LEFT_X, Y_ROWS, LEFT_W, 44))
	_rows_label.name = "BuildRows"
	_canvas.add_child(_rows_label)

	_traits = UiKit.abs_block("", 13, UiKit.COL_MUTED, Rect2i(LEFT_X, Y_TRAIT, LEFT_W, 60))
	_traits.name = "BuildTraits"
	_canvas.add_child(_traits)

	_canvas.add_child(UiKit.abs_label("已学技能（全部生效、无数量上限）", 13, UiKit.COL_ACCENT,
		Rect2i(LEFT_X, Y_SKILLS_HEAD, LEFT_W, 18)))
	# 技能条数随进度增长，用自带滚动的富文本，不用「普通文本 + 滚动容器」（工作流 §5.6）
	_skills = UiKit.abs_log(12, UiKit.COL_TEXT, Rect2i(LEFT_X, Y_SKILLS, LEFT_W, H_SKILLS))
	_skills.name = "BuildSkills"
	_canvas.add_child(_skills)

	_detail_head = UiKit.abs_label("选中物品", 13, UiKit.COL_ACCENT,
		Rect2i(LEFT_X, Y_DETAIL_HEAD, LEFT_W, 18))
	_detail_head.name = "BuildDetailHead"
	_canvas.add_child(_detail_head)
	_detail = UiKit.abs_block("", 12, UiKit.COL_TEXT, Rect2i(LEFT_X, Y_DETAIL, LEFT_W, H_DETAIL))
	_detail.name = "BuildDetail"
	_canvas.add_child(_detail)

	_canvas.add_child(UiKit.abs_block(
		"点物品格选中，再用顶部操作条执行装备／卸下／合成／使用／丢弃。\n"
		+ "容量校验按操作后的总占用计算，失败不移动半件物品、不扣币不丢物。\n"
		+ "战斗栏与背包都是 10 点容量，物品按大小占格（小 1／中 2／大 3），不堆叠。",
		12, UiKit.COL_MUTED, Rect2i(LEFT_X, Y_LEGEND, LEFT_W, 64)))


func _build_panel() -> void:
	_panel = PanelInventory.new()
	_panel.name = "InventoryPanel"
	_canvas.add_child(_panel)
	_panel.build()
	_panel.cell_selected.connect(_on_cell_selected)
	_panel.op_pressed.connect(_on_op)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var state := ctrl.state
	_rows_label.text = "上排 · 战斗栏：占用 %d / %d 点\n下排 · 背包：占用 %d / %d 点" % [
		state.bar_used(), RunState.BAR_CAPACITY,
		state.inventory_used(), RunState.INVENTORY_CAPACITY,
	]
	var prof := catalog.trait_by_id(state.profession)
	var bl := catalog.trait_by_id(state.bloodline)
	_traits.text = "职业：%s　血统：%s\n%s" % [
		prof.display_name if prof != null else "无",
		bl.display_name if bl != null else "无",
		"　".join([
			prof.description if prof != null else "",
			bl.description if bl != null else "",
		]),
	]
	_skills.text = _skills_text()

	var bar_entries := _entries(state.battle_bar, "bar")
	var inv_entries := _entries(state.inventory, "inv")
	_reaim_selection(bar_entries, inv_entries)
	_panel.set_row(InventorySkin.ROW_A, bar_entries, RunState.BAR_CAPACITY)
	_panel.set_row(InventorySkin.ROW_B, inv_entries, RunState.INVENTORY_CAPACITY)
	_panel.set_ops(_ops_for_selection())
	_refresh_detail()


func _entries(items: Array, where: String) -> Array:
	var out: Array = []
	for it in items:
		var def := catalog.item(it.definition_id)
		var size := def.size if def != null else 1
		# 格子窄，主标题只放物品名（品质与格数交给小字行，试炼成长用角标补）。
		# 注意：ItemInstance.display_name 是带 catalog 参数的方法，不是属性，别当属性读。
		var title := def.display_name if def != null else String(it.definition_id)
		if it.trial_growth != 0.0:
			title += " ▲"
		out.append({
			"id": "%s:%s" % [where, it.instance_id],
			"instance_id": it.instance_id,
			"definition_id": it.definition_id,
			"name": title,
			"sub": "%s·%d格" % [PriceTable.quality_name(it.quality), size],
			"quality": it.quality,
			"size": size,
			"enabled": true,
		})
	return out


## 操作后物品常在战斗栏与背包之间搬动，选中项换个行也要跟着走，否则每点一次都掉选中。
func _reaim_selection(bar_entries: Array, inv_entries: Array) -> void:
	if _sel_instance == "":
		return
	var want := _sel_instance
	_sel_id = ""
	for e in bar_entries + inv_entries:
		if String((e as Dictionary).get("instance_id", "")) == want:
			_sel_id = String((e as Dictionary)["id"])
			_sel_row = InventorySkin.ROW_A if String(_sel_id).begins_with("bar:") else InventorySkin.ROW_B
			break
	if _sel_id != _panel.selected():
		_panel.set_selected(_sel_id)


func _selected_entry() -> Dictionary:
	if _sel_id == "":
		return {}
	for it in ctrl.state.battle_bar:
		if _sel_id == "bar:%s" % it.instance_id:
			return _entry_of(it, "bar")
	for it in ctrl.state.inventory:
		if _sel_id == "inv:%s" % it.instance_id:
			return _entry_of(it, "inv")
	return {}


func _entry_of(it: ItemInstance, where: String) -> Dictionary:
	var def := catalog.item(it.definition_id)
	return {
		"id": "%s:%s" % [where, it.instance_id],
		"instance_id": it.instance_id,
		"definition_id": it.definition_id,
		"name": it.display_name,
		"sub": "%s·%d格" % [PriceTable.quality_name(it.quality), def.size if def != null else 1],
		"quality": it.quality,
		"size": def.size if def != null else 1,
		"enabled": true,
	}


func _synth_target(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var cands := ctrl.inventory.synthesis_candidates(ctrl.state, String(entry.get("instance_id", "")))
	return String(cands[0]) if not cands.is_empty() else ""


func _ops_for_selection() -> Array:
	var e := _selected_entry()
	var has := not e.is_empty()
	var from_bar := _sel_row == InventorySkin.ROW_A
	var def: ItemDef = catalog.item(String(e.get("definition_id", ""))) if has else null
	var can_equip := has and not from_bar and def != null and def.equippable
	var can_use := has and def != null and def.category == ItemDef.CAT_CONSUMABLE \
		and ctrl.state.current_hp < ctrl.state.max_hp
	return [
		{"id": "equip", "label": "装备", "disabled": not can_equip},
		{"id": "unequip", "label": "卸下", "disabled": not (has and from_bar)},
		{"id": "use", "label": "使用", "disabled": not can_use},
		{"id": "synth", "label": "合成", "disabled": not has or _synth_target(e).is_empty()},
		{"id": "discard", "label": "丢弃", "disabled": not has},
		{"id": "leave", "label": "返回", "align": "right"},
	]


func _refresh_detail() -> void:
	var e := _selected_entry()
	if e.is_empty():
		_detail_head.text = "选中物品（未选中）"
		_detail.text = "点两行里的任意物品格即可选中；操作条上不可用的按钮是灰的。"
		return
	var it := _instance_of(String(e.get("instance_id", "")))
	var def := catalog.item(String(e.get("definition_id", "")))
	_detail_head.text = "选中物品：%s" % String(e.get("name", ""))
	var lines := PackedStringArray()
	lines.append("[%s] %s　%s" % [
		"战斗栏" if _sel_row == InventorySkin.ROW_A else "背包",
		item_line(it) if it != null else String(e.get("name", "")),
		String(e.get("sub", "")),
	])
	if def != null:
		lines.append("%d 格　CD %.1f 秒　%s" % [def.size, float(def.cooldown_ms) / 1000.0,
			UiKit.effect_text(def)])
		var tg := UiKit.trigger_text(def)
		if tg != "":
			lines.append(tg)
		var price := PriceTable.item_sell_price(def, int(e.get("quality", 0)))
		lines.append("出售回收 %d 货币" % price)
	_detail.text = "\n".join(lines)


func _instance_of(instance_id: String) -> ItemInstance:
	for it in ctrl.state.battle_bar:
		if it.instance_id == instance_id:
			return it
	for it in ctrl.state.inventory:
		if it.instance_id == instance_id:
			return it
	return null


func _skills_text() -> String:
	var state := ctrl.state
	if state.skills.is_empty():
		return "尚未学会技能。\n（战斗中击败对手后有机会掉落技能，购买商店技能直接学会。）"
	var lines := PackedStringArray()
	for k in state.skills.keys():
		var ss: SkillState = state.skills[k]
		var sd := catalog.skill(k)
		lines.append("· %s（%s）" % [catalog.skill_display(k), PriceTable.quality_name(ss.quality)])
		if sd != null:
			lines.append("　　触发「%s」→ %s %.1f" % [sd.trigger_event, sd.effect_type,
				sd.value_at(ss.quality)])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_cell_selected(row: String, _index: int, _entries_index: int) -> void:
	_sel_id = _panel.selected()
	_sel_row = row
	_sel_instance = "" if _sel_id == "" else _sel_id.split(":", true, 1)[1]
	_panel.set_ops(_ops_for_selection())
	_refresh_detail()


func _on_op(op_id: String) -> void:
	var e := _selected_entry()
	var iid := String(e.get("instance_id", ""))
	match op_id:
		"equip":
			_do(ctrl.equip(iid))
		"unequip":
			_do(ctrl.unequip(iid))
		"use":
			_do(ctrl.use_recovery(iid))
		"synth":
			var target := _synth_target(e)
			if not target.is_empty():
				_do(ctrl.synthesize(iid, target))
		"discard":
			_do(ctrl.discard_item(iid))
		"leave":
			ctrl.close_build()


func _do(result: OperationResult) -> void:
	_note.text = result.reason if result != null else ""
	_refresh()


# ---------------------------------------------------------------------------
# 布局自检
# ---------------------------------------------------------------------------

func layout_report() -> Dictionary:
	if _panel == null:
		return {}
	var rep := _panel.report()
	rep["canvas_min"] = Vector2i(_canvas.custom_minimum_size)
	rep["canvas"] = Vector2i(_canvas.size)
	rep["design"] = InventorySkin.design_size()
	rep["panel_rect"] = InventorySkin.rect(InventorySkin.PANEL)
	rep["inner"] = InventorySkin.inner(InventorySkin.PANEL)
	rep["skills"] = {
		"rect": Rect2i(Vector2i(_skills.position), Vector2i(_skills.size)),
		"chars": _skills.get_total_character_count(),
		"lines": _skills.get_line_count(),
	}
	return rep
