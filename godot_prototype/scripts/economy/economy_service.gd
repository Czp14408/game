class_name EconomyService
extends RefCounted
## 买卖、刷新、锁定与账本。钱与物品一次性提交，失败不扣币不丢物。
## 依据：游戏可玩原型技术方案.md 第 11/13 节；游戏最小战斗与经济方案.md 第 6 节。

var catalog: ContentCatalog
var inventory: InventoryService
var shops: ShopService
var recorder: SessionRecorder
var ledger: Array[Dictionary] = []


func _init(p_catalog: ContentCatalog = null) -> void:
	catalog = p_catalog
	inventory = InventoryService.new(p_catalog)
	shops = ShopService.new(p_catalog)


func bind_rng(rng: RandomService) -> void:
	shops.rng = rng


func _record(kind: String, amount: int, reason: String, detail: Dictionary = {}) -> void:
	var entry := {"kind": kind, "amount": amount, "reason": reason, "detail": detail}
	ledger.append(entry)
	if recorder != null:
		recorder.record_event("economy", entry)


# ---------------------------------------------------------------------------
# 购买
# ---------------------------------------------------------------------------

func price_of_slot(slot: ShopState.Slot) -> int:
	if slot.is_skill:
		return PriceTable.skill_base_price(slot.quality)
	var def := catalog.item(slot.item.definition_id)
	return PriceTable.item_base_price(def, slot.quality)


func buy(state: RunState, shop_state: ShopState, slot_index: int) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if shop_state == null or slot_index < 0 or slot_index >= shop_state.slots.size():
		return OperationResult.fail("商品位无效")
	var slot: ShopState.Slot = shop_state.slots[slot_index]
	# 防重复：shop_id + slot_id 购买状态
	if slot.purchased:
		return OperationResult.fail("该商品已买走")

	var price := price_of_slot(slot)
	if state.money < price:
		return OperationResult.fail("余额不足（需要 %d，现有 %d）" % [price, state.money])

	if slot.is_skill:
		var lr := learn_skill(state, slot.skill_id, slot.quality)
		if not lr.success:
			return lr
		state.spend_money(price)
		slot.purchased = true
		_record("buy_skill", -price, "技能购买：%s" % catalog.skill_display(slot.skill_id))
		return OperationResult.ok({"spent": price, "skill": String(slot.skill_id)})

	# 物品：进入背包并触发自动合成（§8）。合成后按最终占用校验容量，失败整次回退。
	var it := slot.item
	it.origin_node = shop_state.shop_key
	var sr := inventory.auto_synthesize_into(state, it)
	if not sr.success:
		return OperationResult.fail(sr.reason)
	state.spend_money(price)
	slot.purchased = true
	_record("buy_item", -price, "物品购买：%s（%s）" % [catalog.item_display(it.definition_id), PriceTable.quality_name(it.quality)])
	# instance_id 用最终产物（合并发生时购入件已被消耗）
	return OperationResult.ok({"spent": price, "instance_id": String(sr.data.get("instance_id", it.instance_id)),
		"merged": sr.data.get("merged", 0), "produced_quality": sr.data.get("produced_quality", it.quality)})


## 购买到指定位置：商品拖入背包（dst="inv"）或战斗栏（dst="bar"）的 target_index。
## 物品购买会触发入背包自动合成；技能购买直接学习（技能不占物品格）。
## 整次原子提交：失败不扣币、不消耗货位、不留半件物品。
## 依据：游戏主界面与交互调整方案.md §7 商品拖拽购买、§8 入包自动合成。
func buy_into(state: RunState, shop_state: ShopState, slot_index: int,
		dst: String, target_index: int) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if shop_state == null or slot_index < 0 or slot_index >= shop_state.slots.size():
		return OperationResult.fail("商品位无效")
	var slot: ShopState.Slot = shop_state.slots[slot_index]
	if slot.purchased:
		return OperationResult.fail("该商品已买走")
	var price := price_of_slot(slot)
	if state.money < price:
		return OperationResult.fail("余额不足（需要 %d，现有 %d）" % [price, state.money])

	if slot.is_skill:
		# 技能：直接学习，不占物品格；dst/target_index 忽略
		var lr := learn_skill(state, slot.skill_id, slot.quality)
		if not lr.success:
			return lr
		state.spend_money(price)
		slot.purchased = true
		_record("buy_skill", -price, "技能购买：%s" % catalog.skill_display(slot.skill_id))
		return OperationResult.ok({"spent": price, "skill": String(slot.skill_id)})

	# 物品：先按目标栏构造副本校验（不真正改动状态），通过后才提交。
	var it := slot.item
	if dst != "bar" and dst != "inv":
		return OperationResult.fail("目标栏无效")

	if dst == "bar":
		var def := catalog.item(it.definition_id)
		if def == null or not def.equippable:
			return OperationResult.fail("该商品不能放入战斗栏")
		if def.category == ItemDef.CAT_CONSUMABLE:
			return OperationResult.fail("恢复品不进入战斗栏")
		# 直接进入战斗栏不触发自动合成（§8：进入战斗栏不合成）
		var new_bar: Array = state.battle_bar.duplicate()
		new_bar.erase(it)
		inventory._insert_at(new_bar, it, target_index)
		if not state.fits_after(new_bar, state.inventory.duplicate()):
			return OperationResult.fail("战斗栏空间不足")
		state.spend_money(price)
		slot.purchased = true
		it.origin_node = shop_state.shop_key
		inventory._commit(state, new_bar, state.inventory.duplicate())
		state.register_instance(it)
		_record("buy_item", -price, "物品购买：%s（%s）" % [catalog.item_display(it.definition_id), PriceTable.quality_name(it.quality)])
		return OperationResult.ok({"spent": price, "instance_id": it.instance_id})

	# 目标背包：触发入背包自动合成（§8）。
	# 先扣币/占位标记必须在合成成功后才提交，失败整次回退。
	it.origin_node = shop_state.shop_key
	var sr := inventory.auto_synthesize_into(state, it)
	if not sr.success:
		return OperationResult.fail(sr.reason)
	state.spend_money(price)
	slot.purchased = true
	_record("buy_item", -price, "物品购买：%s（%s）" % [catalog.item_display(it.definition_id), PriceTable.quality_name(it.quality)])
	# instance_id 用最终产物（合并发生时购入件已被消耗）
	return OperationResult.ok({"spent": price, "instance_id": String(sr.data.get("instance_id", it.instance_id)),
		"merged": sr.data.get("merged", 0), "produced_quality": sr.data.get("produced_quality", it.quality)})


# ---------------------------------------------------------------------------
# 出售
# ---------------------------------------------------------------------------

func sell(state: RunState, instance_id: String, shop_key: String) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if shop_key == "":
		return OperationResult.fail("只能在商店出售")
	if not state.is_held(instance_id):
		return OperationResult.fail("实例不存在或已不持有")
	var it := state.instance(instance_id)
	var def := catalog.item(it.definition_id)
	if def == null:
		return OperationResult.fail("定义缺失")
	var price := PriceTable.item_sell_price(def, it.quality)
	var dr := inventory.discard(state, instance_id)
	if not dr.success:
		return OperationResult.fail(dr.reason)
	state.add_money(price)
	_record("sell_item", price, "出售：%s（%s）" % [catalog.item_display(it.definition_id), PriceTable.quality_name(it.quality)])
	return OperationResult.ok({"gain": price})


# ---------------------------------------------------------------------------
# 刷新与锁定
# ---------------------------------------------------------------------------

func refresh(state: RunState, shop_state: ShopState) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if shop_state == null:
		return OperationResult.fail("商店无效")
	if shop_state.locked:
		return OperationResult.fail("商品已锁定，请先解锁再刷新")
	var def := catalog.shop(shop_state.shop_id)
	if def == null:
		return OperationResult.fail("商店定义缺失")
	if state.money < def.refresh_cost:
		return OperationResult.fail("余额不足（刷新需要 %d）" % def.refresh_cost)

	state.spend_money(def.refresh_cost)
	var fresh := shops.regenerate(state, shop_state)
	_replace_shop(state, shop_state, fresh)
	_record("refresh_shop", -def.refresh_cost, "刷新：%s" % shop_state.shop_key)
	return OperationResult.ok({"cost": def.refresh_cost, "shop_key": shop_state.shop_key})


func set_lock(state: RunState, shop_state: ShopState, locked: bool) -> OperationResult:
	if shop_state == null:
		return OperationResult.fail("商店无效")
	shop_state.locked = locked
	_record("lock_shop", 0, "%s：%s" % ["锁定" if locked else "解锁", shop_state.shop_key])
	return OperationResult.ok({"locked": locked})


func _replace_shop(state: RunState, old: ShopState, fresh: ShopState) -> void:
	var parts := old.shop_key.split("/")
	var ns := state.node_state(parts[0])
	ns.shops[old.shop_id] = fresh


# ---------------------------------------------------------------------------
# 技能学习（购买后立即学习，不生成可携带载体）
# ---------------------------------------------------------------------------

func learn_skill(state: RunState, skill_id: StringName, quality: int) -> OperationResult:
	if catalog.skill(skill_id) == null:
		return OperationResult.fail("技能定义不存在")
	var existing: SkillState = state.skills.get(skill_id)
	if existing == null:
		state.skills[skill_id] = SkillState.make(skill_id, quality)
		_record("learn_skill", 0, "学会：%s（%s）" % [catalog.skill_display(skill_id), PriceTable.quality_name(quality)])
		return OperationResult.ok({"learned": String(skill_id), "quality": quality})
	if existing.quality == quality:
		if quality >= ContentCatalog.MAX_QUALITY:
			return OperationResult.fail("最高品质技能不再通过重复技能提升")
		existing.quality += 1
		_record("synthesize_skill", 0, "同名同品质技能合成：%s（%s）" % [catalog.skill_display(skill_id), PriceTable.quality_name(existing.quality)])
		return OperationResult.ok({"learned": String(skill_id), "quality": existing.quality})
	if quality > existing.quality:
		# 高品質替换保留本次试炼成长；低品质不降级
		existing.quality = quality
		_record("replace_skill", 0, "替换为更高品质：%s（%s）" % [catalog.skill_display(skill_id), PriceTable.quality_name(quality)])
		return OperationResult.ok({"learned": String(skill_id), "quality": quality})
	return OperationResult.fail("已有更高品质的同名技能，低品质不降级")
