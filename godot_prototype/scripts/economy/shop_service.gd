class_name ShopService
extends RefCounted
## 随机商店生成：类别/品质权重、买走留空、付费刷新整批商品。
## 边界：查看商店界面不消耗随机数。
## 依据：游戏最小战斗与经济方案.md 第 6 节；技术方案 第 12 节。

var catalog: ContentCatalog
var rng: RandomService


func _init(p_catalog: ContentCatalog = null, p_rng: RandomService = null) -> void:
	catalog = p_catalog
	rng = p_rng


func state_for(state: RunState, node_id: String, shop_id: StringName) -> ShopState:
	var ns := state.node_state(node_id)
	var existing: ShopState = ns.shops.get(shop_id)
	if existing != null:
		return existing
	var def := catalog.shop(shop_id)
	if def == null:
		return null
	var s := _generate(state, "%s/%s" % [node_id, shop_id], def)
	ns.shops[shop_id] = s
	return s


func deity_shop(state: RunState) -> ShopState:
	var ns := state.node_state("__deity__")
	var shop: ShopState = ns.shops.get(&"deity_mixed")
	if shop != null:
		return shop
	var def := catalog.shop(&"deity_mixed")
	var s := _generate(state, "deity/deity_mixed", def)
	ns.shops[&"deity_mixed"] = s
	return s


func regenerate(state: RunState, shop_state: ShopState) -> ShopState:
	var def := catalog.shop(shop_state.shop_id)
	if def == null:
		return shop_state
	shop_state.refresh_serial += 1
	var fresh := _generate(state, shop_state.shop_key, def)
	fresh.locked = shop_state.locked
	fresh.refresh_serial = shop_state.refresh_serial
	return fresh


func _generate(state: RunState, shop_key: String, def: ShopDef) -> ShopState:
	var s := ShopState.new()
	s.shop_key = shop_key
	s.shop_id = def.shop_id
	s.initialized = true
	var scope := "shop/%s" % shop_key
	for i in def.item_count:
		s.slots.append(_roll_slot(state, def, scope))
	return s


func _roll_slot(state: RunState, def: ShopDef, scope: String) -> ShopState.Slot:
	var slot := ShopState.Slot.new()
	var is_skill := false
	var pool: Array = []
	if def.mode == ShopDef.MODE_MIXED:
		# 每格先抽装备 80% / 技能 20%，然后各自池内等概率
		var kind_idx := rng.pick_weighted(scope, [def.equipment_weight, def.skill_weight])
		if kind_idx == 1:
			is_skill = true
			pool = def.skill_candidates
		else:
			pool = def.equipment_pool
	else:
		# 候选池内等概率（物品与技能同池竞争）
		for entry in def.item_candidates:
			pool.append({"id": entry, "is_skill": false})
		for entry in def.skill_candidates:
			pool.append({"id": entry, "is_skill": true})

	if pool.is_empty():
		return slot

	var idx := rng.rand_index(scope, pool.size())
	if def.mode == ShopDef.MODE_MIXED:
		var pick_id: StringName = pool[idx]
		is_skill = def.skill_candidates.has(pick_id) and not def.equipment_pool.has(pick_id)
		_assign(slot, state, pick_id, is_skill, def, scope)
	else:
		var entry: Dictionary = pool[idx]
		_assign(slot, state, entry["id"], bool(entry["is_skill"]), def, scope)
	return slot


func _assign(slot: ShopState.Slot, state: RunState, id: StringName, is_skill: bool, def: ShopDef, scope: String) -> void:
	slot.is_skill = is_skill
	if is_skill:
		slot.skill_id = id
		slot.quality = _roll_quality(def, scope)
		return
	var item_def := catalog.item(id)
	var quality := 0
	# 恢复品与材料没有四档效果，不为它生成无意义品质
	if item_def != null and item_def.tier_values.size() == 4 and item_def.fixed_base_price < 0:
		quality = _roll_quality(def, scope)
	elif item_def != null and item_def.category == ItemDef.CAT_CONSUMABLE:
		quality = 0
	slot.quality = quality
	var it := state.new_instance(id, quality, "")
	it.location = ItemInstance.LOC_NONE
	slot.item = it


func _roll_quality(def: ShopDef, scope: String) -> int:
	var idx := rng.pick_weighted(scope, def.quality_weights)
	return maxi(idx, 0)
