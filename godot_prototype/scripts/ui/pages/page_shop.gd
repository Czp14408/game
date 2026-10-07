class_name PageShop
extends PageBase
## 商店：购买、出售、刷新与锁定。买走不补位；技能购买直接学习。
## 右侧用「背包／商店／整理共用面板」的商店模式——上排商品货位、下排背包待售。
## 依据：技术方案第 11、12 节；游戏最小战斗与经济方案.md 第 6 节；
## 背包商店整理共用面板说明.md；ui修改迭代工作流.md。

const LEFT_X := 16
const LEFT_W := 620
const Y_TITLE := 12
const Y_SHOP := 46
const Y_STATE := 76
const Y_NOTE := 132
const Y_DETAIL_HEAD := 200
const Y_DETAIL := 222
const H_DETAIL := 150
const Y_LEGEND := 392

## §2「商店在屏幕上方横向展开」：共用面板在商店页落位画布右上，
## 覆盖清单里的默认落位（右侧居中是 R0.7 历史基线，构筑/整理页仍按清单落位）。
const PANEL_TOP_Y := 46
const PANEL_MARGIN_R := 16

var _canvas: Control
var _panel: PanelInventory
var _shop_label: Label
var _state_label: Label
var _note: Label
var _detail_head: Label
var _detail: Label

var _sel_id := ""
var _sel_kind := ""      ## "goods" / "bag"


func build() -> void:
	# 页面区第一层必须是铺满宽度的容器：真渲染布局断言据此判断页面没被压窄。
	var center := CenterContainer.new()
	center.name = "ShopCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_canvas = Control.new()
	_canvas.name = "DesignCanvas"
	var design := InventorySkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_canvas.custom_minimum_size = Vector2(design)
	center.add_child(_canvas)
	_canvas.add_child(UiKit.solid(UiKit.COL_BG, Rect2i(Vector2i.ZERO, design)))

	_build_left()
	_build_panel()
	_refresh()


func _build_left() -> void:
	_canvas.add_child(UiKit.abs_label("商店", 20, UiKit.COL_ACCENT, Rect2i(LEFT_X, Y_TITLE, LEFT_W, 28)))
	_shop_label = UiKit.abs_label("", 15, UiKit.COL_TEXT, Rect2i(LEFT_X, Y_SHOP, LEFT_W, 24))
	_shop_label.name = "ShopName"
	_canvas.add_child(_shop_label)
	_state_label = UiKit.abs_block("", 13, UiKit.COL_MUTED, Rect2i(LEFT_X, Y_STATE, LEFT_W, 44))
	_state_label.name = "ShopState"
	_canvas.add_child(_state_label)
	_note = UiKit.abs_block("", 13, UiKit.COL_ACCENT, Rect2i(LEFT_X, Y_NOTE, LEFT_W, 60))
	_note.name = "ShopNote"
	_canvas.add_child(_note)
	_detail_head = UiKit.abs_label("选中物品", 13, UiKit.COL_ACCENT,
		Rect2i(LEFT_X, Y_DETAIL_HEAD, LEFT_W, 18))
	_detail_head.name = "ShopDetailHead"
	_canvas.add_child(_detail_head)
	_detail = UiKit.abs_block("", 12, UiKit.COL_TEXT, Rect2i(LEFT_X, Y_DETAIL, LEFT_W, H_DETAIL))
	_detail.name = "ShopDetail"
	_canvas.add_child(_detail)
	_canvas.add_child(UiKit.abs_block(
		"上排是商品货位（买走不补位，允许重复商品），下排是背包里可出售的物品。\n"
		+ "出售按标准价一半回收；技能不能出售。出售只针对背包，要卖战斗栏里的东西\n"
		+ "先去「构筑与整理」卸下。刷新整批商品与锁定开关都在操作条上。",
		12, UiKit.COL_MUTED, Rect2i(LEFT_X, Y_LEGEND, LEFT_W, 66)))


func _build_panel() -> void:
	_panel = PanelInventory.new()
	_panel.name = "InventoryPanel"
	_canvas.add_child(_panel)
	_panel.build()
	# §2 商店在屏幕上方：面板贴画布右上（清单矩形只定尺寸，落位由本页覆盖）。
	var pr := InventorySkin.rect(InventorySkin.PANEL)
	var design := InventorySkin.design_size()
	if design == Vector2i.ZERO:
		design = Vector2i(1280, 690)
	_panel.position = Vector2(design.x - pr.size.x - PANEL_MARGIN_R, PANEL_TOP_Y)
	_panel.cell_selected.connect(_on_cell_selected)
	_panel.op_pressed.connect(_on_op)


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var shop := ctrl.current_shop()
	if shop == null:
		_shop_label.text = "商店不存在。"
		_state_label.text = ""
		_panel.set_row(InventorySkin.ROW_A, [], 0)
		_panel.set_row(InventorySkin.ROW_B, [], 0)
		_panel.set_ops([{"id": "leave", "label": "离开", "align": "right"}])
		_detail_head.text = "选中物品（未选中）"
		_detail.text = ""
		return

	var def := catalog.shop(shop.shop_id)
	var refresh_cost := def.refresh_cost if def != null else 0
	_shop_label.text = def.display_name if def != null else "商店"
	_state_label.text = "货币 %d　刷新费 %d　已刷新 %d 次\n货位 %d 个　状态：%s" % [
		ctrl.state.money, refresh_cost, shop.refresh_serial, shop.slots.size(),
		"已锁定（刷新不可用）" if shop.locked else "未锁定",
	]

	var goods: Array = []
	for i in shop.slots.size():
		goods.append(_goods_entry(i, shop.slots[i]))
	var bag: Array = []
	for it in ctrl.state.inventory:
		bag.append(_bag_entry(it))

	_reaim_selection(goods, bag)
	# 商品是位置固定的货位，启用格数就等于货位数；背包固定 10 点
	_panel.set_row(InventorySkin.ROW_A, goods, shop.slots.size())
	_panel.set_row(InventorySkin.ROW_B, bag, RunState.INVENTORY_CAPACITY)
	_panel.set_ops(_ops_for_selection())
	_refresh_detail()


func _goods_entry(index: int, slot: ShopState.Slot) -> Dictionary:
	if slot.purchased:
		return {"id": "goods:%d" % index, "index": index, "name": "已售出", "sub": "不补位",
			"quality": -1, "size": 1, "enabled": false}
	var price := ctrl.economy.price_of_slot(slot)
	var name := ""
	var sub := "%d 货币" % price
	if slot.is_skill:
		name = "技能·%s" % catalog.skill_display(slot.skill_id)
		sub = "技能　%d 货币" % price
	else:
		var idef := catalog.item(slot.item.definition_id)
		name = catalog.item_display(slot.item.definition_id)
		sub = "%s·%d 格　%d" % [PriceTable.quality_name(slot.quality),
			idef.size if idef != null else 1, price]
	return {"id": "goods:%d" % index, "index": index, "name": name, "sub": sub,
		"quality": slot.quality, "size": 1, "enabled": true}


func _bag_entry(it: ItemInstance) -> Dictionary:
	var def := catalog.item(it.definition_id)
	var price := PriceTable.item_sell_price(def, it.quality)
	# 格子窄，主标题只放物品名；注意 display_name 是带 catalog 参数的方法，不是属性。
	var title := def.display_name if def != null else String(it.definition_id)
	if it.trial_growth != 0.0:
		title += " ▲"
	return {
		"id": "bag:%s" % it.instance_id,
		"instance_id": it.instance_id,
		"definition_id": it.definition_id,
		"name": title,
		"sub": "%s·回收 %d" % [PriceTable.quality_name(it.quality), price],
		"quality": it.quality,
		"size": def.size if def != null else 1,
		"enabled": true,
	}


func _reaim_selection(goods: Array, bag: Array) -> void:
	if _sel_id == "":
		return
	var still := false
	for e in goods + bag:
		if String((e as Dictionary).get("id", "")) == _sel_id:
			still = true
			break
	if not still:
		_sel_id = ""
		_panel.set_selected("")
	elif _sel_id != _panel.selected():
		_panel.set_selected(_sel_id)


func _selected_entry() -> Dictionary:
	var shop := ctrl.current_shop()
	if _sel_id == "" or shop == null:
		return {}
	if _sel_id.begins_with("goods:"):
		var i := int(_sel_id.split(":", true, 1)[1])
		if i >= 0 and i < shop.slots.size():
			return _goods_entry(i, shop.slots[i])
		return {}
	var iid := _sel_id.split(":", true, 1)[1]
	for it in ctrl.state.inventory:
		if it.instance_id == iid:
			return _bag_entry(it)
	return {}


func _ops_for_selection() -> Array:
	var shop := ctrl.current_shop()
	var e := _selected_entry()
	var def := catalog.shop(shop.shop_id) if shop != null else null
	var refresh_cost := def.refresh_cost if def != null else 0
	var can_buy := not e.is_empty() and _sel_kind == "goods" and bool(e.get("enabled", true)) \
		and ctrl.state.money >= ctrl.economy.price_of_slot(shop.slots[int(e.get("index", 0))])
	var can_sell := not e.is_empty() and _sel_kind == "bag"
	var can_refresh := shop != null and not shop.locked and ctrl.state.money >= refresh_cost
	return [
		{"id": "buy", "label": "购买", "disabled": not can_buy},
		{"id": "sell", "label": "出售", "disabled": not can_sell},
		{"id": "refresh", "label": "刷新", "disabled": not can_refresh},
		{"id": "lock", "label": "解锁" if (shop != null and shop.locked) else "锁定",
			"disabled": shop == null},
		{"id": "leave", "label": "离开", "align": "right"},
	]


func _refresh_detail() -> void:
	var e := _selected_entry()
	if e.is_empty():
		_detail_head.text = "选中物品（未选中）"
		_detail.text = "点上排商品看价格与效果，点下排背包物品看回收价。\n未选中的操作按钮是灰的。"
		return
	_detail_head.text = "选中：%s" % String(e.get("name", ""))
	var lines := PackedStringArray()
	if _sel_kind == "goods":
		var shop := ctrl.current_shop()
		var slot: ShopState.Slot = shop.slots[int(e.get("index", 0))]
		var price := ctrl.economy.price_of_slot(slot)
		lines.append("价格 %d 货币　现有 %d" % [price, ctrl.state.money])
		if slot.is_skill:
			var sd := catalog.skill(slot.skill_id)
			if sd != null:
				lines.append("技能（不占战斗栏格）　品质 %s" % PriceTable.quality_name(slot.quality))
				lines.append("触发「%s」→ %s %.1f" % [sd.trigger_event, sd.effect_type,
					sd.value_at(slot.quality)])
			lines.append("购买后直接学会，无需装备。")
		else:
			var idef := catalog.item(slot.item.definition_id)
			if idef != null:
				lines.append("%d 格　CD %.1f 秒　%s" % [idef.size, float(idef.cooldown_ms) / 1000.0,
					UiKit.effect_text(idef)])
				var tg := UiKit.trigger_text(idef)
				if tg != "":
					lines.append(tg)
		if price > ctrl.state.money:
			lines.append("余额不足，需要 %d，现有 %d。" % [price, ctrl.state.money])
		if not slot.purchased and not _panel.selected().is_empty():
			lines.append("买走后该货位不会补位。")
	else:
		var def := catalog.item(String(e.get("definition_id", "")))
		var price := PriceTable.item_sell_price(def, int(e.get("quality", 0)))
		lines.append("回收 %d 货币（标准价一半）" % price)
		if def != null:
			lines.append("%d 格　CD %.1f 秒　%s" % [def.size, float(def.cooldown_ms) / 1000.0,
				UiKit.effect_text(def)])
	_detail.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_cell_selected(_row: String, _index: int, _entries_index: int) -> void:
	_sel_id = _panel.selected()
	_sel_kind = _sel_id.split(":", true, 1)[0] if _sel_id != "" else ""
	_panel.set_ops(_ops_for_selection())
	_refresh_detail()


func _on_op(op_id: String) -> void:
	match op_id:
		"buy":
			var e := _selected_entry()
			if not e.is_empty():
				var r := ctrl.buy_slot(int(e.get("index", 0)))
				_note.text = _result_text(r)
				_refresh()
				_flash_buy_result(r)
				return
		"sell":
			var b := _selected_entry()
			if not b.is_empty():
				_note.text = _result_text(ctrl.sell(String(b.get("instance_id", ""))))
		"refresh":
			_note.text = _result_text(ctrl.refresh_shop())
		"lock":
			ctrl.toggle_shop_lock()
			var shop := ctrl.current_shop()
			_note.text = "已锁定本次商品，刷新不可用。" if (shop != null and shop.locked) \
				else "已解锁，可以刷新整批商品。"
		"leave":
			ctrl.close_shop()
			return
	_refresh()


## 购买后的入包反馈（§11）：在最终产物落位的背包格上短暂闪光；
## 发生合成时合并为一条品质变化提示，不弹确认窗口。
func _flash_buy_result(r: OperationResult) -> void:
	if r == null or not r.success:
		return
	var iid := String(r.data.get("instance_id", ""))
	var cell := _panel.cell_by_id(InventorySkin.ROW_B, "bag:%s" % iid)
	if cell != null:
		UiKit.flash_control(cell)
	var merged := int(r.data.get("merged", 0))
	if merged > 0:
		var q := int(r.data.get("produced_quality", 0))
		_note.text = "自动合成 ×%d → %s" % [merged, PriceTable.quality_name(q)]


func _result_text(result: OperationResult) -> String:
	if result == null:
		return ""
	return "%s%s" % ["" if result.success else "失败：", result.reason]


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
	# panel_rect 报实际落位（商店页覆盖到屏幕上方）；清单矩形另存一份备查。
	rep["panel_rect"] = Rect2i(Vector2i(_panel.position), Vector2i(_panel.size))
	rep["panel_rect_manifest"] = InventorySkin.rect(InventorySkin.PANEL)
	rep["inner"] = InventorySkin.inner(InventorySkin.PANEL)
	return rep
