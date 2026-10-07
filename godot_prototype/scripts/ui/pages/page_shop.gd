class_name PageShop
extends PageBase
## 商店：购买、出售、刷新与锁定。买走不补位；技能购买直接学习。
## 依据：技术方案第 11、12 节；游戏最小战斗与经济方案.md 第 6 节。

var _slots_box: VBoxContainer
var _sell_box: VBoxContainer
var _hud_label: Label


func build() -> void:
	var root := add_root("商店交易")
	_hud_label = UiKit.label(hud(), 15, UiKit.COL_TEXT)
	root.add_child(_hud_label)

	var shop := ctrl.current_shop()
	if shop == null:
		root.add_child(UiKit.label("商店不存在。", 16, UiKit.COL_ENEMY))
		root.add_child(UiKit.button("离开", func() -> void: ctrl.close_shop()))
		return

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel(catalog.shop(shop.shop_id).display_name if catalog.shop(shop.shop_id) != null else "商品")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lb := UiKit.body(left)
	_slots_box = UiKit.vbox(8)
	lb.add_child(UiKit.scroll_into(_slots_box))

	var right := UiKit.panel("出售与操作")
	right.custom_minimum_size = Vector2(360, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	rb.add_child(UiKit.label("出售按标准价一半回收；技能不能出售。", 13, UiKit.COL_MUTED))
	_sell_box = UiKit.vbox(6)
	rb.add_child(UiKit.scroll_into(_sell_box))
	rb.add_child(UiKit.button("刷新整批商品", _on_refresh))
	rb.add_child(UiKit.button("切换锁定", _on_lock))
	rb.add_child(UiKit.button("离开商店", func() -> void: ctrl.close_shop()))

	_refresh()


func _on_refresh() -> void:
	ctrl.refresh_shop()
	_refresh()


func _on_lock() -> void:
	ctrl.toggle_shop_lock()
	_refresh()


func _on_buy(index: int) -> void:
	ctrl.buy_slot(index)
	_refresh()


func _on_sell(instance_id: String) -> void:
	ctrl.sell(instance_id)
	_refresh()


func _refresh() -> void:
	if _hud_label != null:
		_hud_label.text = hud()
	var shop := ctrl.current_shop()
	if shop == null or _slots_box == null:
		return
	for c in _slots_box.get_children():
		_slots_box.remove_child(c)
		c.queue_free()
	var def := catalog.shop(shop.shop_id)
	var refresh_cost := def.refresh_cost if def != null else 0
	_slots_box.add_child(UiKit.label("商品（买走不补位，允许重复商品）", 15, UiKit.COL_ACCENT))
	_slots_box.add_child(UiKit.label("状态：%s　刷新费 %d 货币　已刷新 %d 次" % [
		"已锁定" if shop.locked else "未锁定", refresh_cost, shop.refresh_serial,
	], 14, UiKit.COL_MUTED))
	for i in shop.slots.size():
		var slot: ShopState.Slot = shop.slots[i]
		var row := UiKit.row(8)
		if slot.purchased:
			row.add_child(UiKit.label("（空位：商品已买走，不补位）", 14, UiKit.COL_MUTED))
			_slots_box.add_child(row)
			continue
		var price := ctrl.economy.price_of_slot(slot)
		var name := ""
		var detail := ""
		if slot.is_skill:
			name = "技能：%s" % catalog.skill_display(slot.skill_id)
			var sd := catalog.skill(slot.skill_id)
			detail = "触发：%s　效果值 %.1f／秒" % [sd.trigger_event, sd.value_at(slot.quality)] if sd != null else ""
		else:
			var idef := catalog.item(slot.item.definition_id)
			name = "%s（%s）" % [catalog.item_display(slot.item.definition_id), PriceTable.quality_name(slot.quality)]
			if idef != null:
				detail = "%d 格　CD %.1f 秒　%s" % [idef.size, float(idef.cooldown_ms) / 1000.0, UiKit.effect_text(idef)]
		row.add_child(UiKit.label("%s　价格 %d" % [name, price], 15, UiKit.COL_TEXT))
		var can_afford := ctrl.state.money >= price
		var b := UiKit.button("购买", _on_buy.bind(i), not can_afford)
		row.add_child(b)
		_slots_box.add_child(row)
		if detail != "":
			_slots_box.add_child(UiKit.label("　　%s" % detail, 13, UiKit.COL_MUTED))
		if not can_afford:
			_slots_box.add_child(UiKit.label("　　余额不足（需要 %d，现有 %d）" % [price, ctrl.state.money], 13, UiKit.COL_ENEMY))

	if _sell_box == null:
		return
	for c in _sell_box.get_children():
		_sell_box.remove_child(c)
		c.queue_free()
	_sell_box.add_child(UiKit.label("可出售物品", 15, UiKit.COL_ACCENT))
	var any := false
	for it in ctrl.state.battle_bar:
		any = true
		_sell_box.add_child(_sell_row("战斗栏", it))
	for it in ctrl.state.inventory:
		any = true
		_sell_box.add_child(_sell_row("背包", it))
	if not any:
		_sell_box.add_child(UiKit.label("没有可出售的物品。", 14, UiKit.COL_MUTED))


func _sell_row(where: String, it: ItemInstance) -> HBoxContainer:
	var row := UiKit.row(6)
	var def := catalog.item(it.definition_id)
	var price := PriceTable.item_sell_price(def, it.quality)
	row.add_child(UiKit.label("[%s] %s　回收 %d" % [where, item_line(it), price], 14, UiKit.COL_TEXT))
	row.add_child(UiKit.button("出售", _on_sell.bind(it.instance_id)))
	return row
