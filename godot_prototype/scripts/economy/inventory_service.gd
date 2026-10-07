class_name InventoryService
extends RefCounted
## 装备、卸下、交换、拾取、丢弃、合成。每次操作先验证容量与持有关系。
## 依据：游戏可玩原型技术方案.md 第 11 节；游戏核心规则定稿.md 第 5 节。

var catalog: ContentCatalog


func _init(p_catalog: ContentCatalog = null) -> void:
	catalog = p_catalog


## 装备：从背包放入战斗栏（或已在战斗栏时视为无变化）
func equip(state: RunState, instance_id: String) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if not state.is_held(instance_id):
		return OperationResult.fail("未持有该物品")
	var it := state.instance(instance_id)
	if it.location == ItemInstance.LOC_BATTLE:
		return OperationResult.fail("该物品已在战斗栏")
	var def := catalog.item(it.definition_id)
	if def == null or not def.equippable:
		return OperationResult.fail("该物品不能放入战斗栏")

	var new_bar: Array = state.battle_bar.duplicate()
	var new_inv: Array = state.inventory.duplicate()
	new_inv.erase(it)
	new_bar.append(it)
	if not state.fits_after(new_bar, new_inv):
		return OperationResult.fail("战斗栏空间不足")

	_commit(state, new_bar, new_inv)
	return OperationResult.ok({"instance_id": instance_id, "to": "battle_bar"})


func unequip(state: RunState, instance_id: String) -> OperationResult:
	if not state.is_held(instance_id):
		return OperationResult.fail("未持有该物品")
	var it := state.instance(instance_id)
	if it.location != ItemInstance.LOC_BATTLE:
		return OperationResult.fail("该物品不在战斗栏")

	var new_bar: Array = state.battle_bar.duplicate()
	var new_inv: Array = state.inventory.duplicate()
	new_bar.erase(it)
	new_inv.append(it)
	if not state.fits_after(new_bar, new_inv):
		return OperationResult.fail("背包空间不足")

	_commit(state, new_bar, new_inv)
	return OperationResult.ok({"instance_id": instance_id, "to": "inventory"})


func _commit(state: RunState, new_bar: Array, new_inv: Array) -> void:
	state.battle_bar = _typed(new_bar)
	state.inventory = _typed(new_inv)
	for it in state.battle_bar:
		it.location = ItemInstance.LOC_BATTLE
	for it in state.inventory:
		it.location = ItemInstance.LOC_INVENTORY


func _typed(arr: Array) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for x in arr:
		out.append(x)
	return out


## 拾取：容量不足时先处理现有物品，再决定是否拾取
func pickup(state: RunState, it: ItemInstance) -> OperationResult:
	var new_inv: Array = state.inventory.duplicate()
	new_inv.append(it)
	if not state.fits_after(state.battle_bar, new_inv):
		return OperationResult.fail("背包空间不足，无法拾取")
	var new_bar: Array = state.battle_bar.duplicate()
	_commit(state, new_bar, new_inv)
	state.register_instance(it)
	return OperationResult.ok({"instance_id": it.instance_id})


func discard(state: RunState, instance_id: String) -> OperationResult:
	if not state.is_held(instance_id):
		return OperationResult.fail("未持有该物品")
	var it := state.instance(instance_id)
	var new_bar: Array = state.battle_bar.duplicate()
	var new_inv: Array = state.inventory.duplicate()
	new_bar.erase(it)
	new_inv.erase(it)
	_commit(state, new_bar, new_inv)
	it.location = ItemInstance.LOC_NONE
	return OperationResult.ok({"instance_id": instance_id})


## 合成：同定义、同品质、非钻石，消耗两实例生成一新实例。
## 基础属性读新档位；试炼成长加总继承；战斗临时成长不参与（战斗外合成已清除）。
func synthesize(state: RunState, id_a: String, id_b: String) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if id_a == id_b:
		return OperationResult.fail("需要两件不同实例")
	if not state.is_held(id_a) or not state.is_held(id_b):
		return OperationResult.fail("原实例已不在持有集合")
	var a := state.instance(id_a)
	var b := state.instance(id_b)
	if a.definition_id != b.definition_id:
		return OperationResult.fail("只能合成同名物品")
	if a.quality != b.quality:
		return OperationResult.fail("只能合成同品质物品")
	if a.quality >= ContentCatalog.MAX_QUALITY:
		return OperationResult.fail("最高品质不再提升")

	var keep_in_bar := a.location == ItemInstance.LOC_BATTLE or b.location == ItemInstance.LOC_BATTLE
	var legacy_growth := a.trial_growth + b.trial_growth

	var new_bar: Array = state.battle_bar.duplicate()
	var new_inv: Array = state.inventory.duplicate()
	new_bar.erase(a)
	new_bar.erase(b)
	new_inv.erase(a)
	new_inv.erase(b)

	var produced := state.new_instance(a.definition_id, a.quality + 1, a.origin_node)
	produced.trial_growth = legacy_growth
	if keep_in_bar:
		new_bar.append(produced)
	else:
		new_inv.append(produced)
	if not state.fits_after(new_bar, new_inv):
		return OperationResult.fail("合成后空间不足")

	a.location = ItemInstance.LOC_NONE
	b.location = ItemInstance.LOC_NONE
	_commit(state, new_bar, new_inv)
	return OperationResult.ok({
		"produced": produced.instance_id,
		"quality": produced.quality,
		"trial_growth": legacy_growth,
	})


## 同名同品质的重复件列表（用于界面提示可合成）
func synthesis_candidates(state: RunState, instance_id: String) -> Array[String]:
	var out: Array[String] = []
	if not state.is_held(instance_id):
		return out
	var it := state.instance(instance_id)
	if it.quality >= ContentCatalog.MAX_QUALITY:
		return out
	for other in state.all_instances():
		if other.instance_id == instance_id:
			continue
		if other.definition_id != it.definition_id or other.quality != it.quality:
			continue
		if other.location == ItemInstance.LOC_NONE:
			continue
		out.append(other.instance_id)
	return out


## 战斗外使用恢复品：消耗一个实例，恢复不超过最大生命；满血时不可用
func use_recovery(state: RunState, instance_id: String) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if not state.is_held(instance_id):
		return OperationResult.fail("未持有该物品")
	var it := state.instance(instance_id)
	var def := catalog.item(it.definition_id)
	if def == null or def.category != ItemDef.CAT_CONSUMABLE:
		return OperationResult.fail("该物品不是战斗外恢复品")
	if state.current_hp >= state.max_hp:
		return OperationResult.fail("生命已满，避免误用")
	if it.location == ItemInstance.LOC_BATTLE:
		return OperationResult.fail("恢复品不进入战斗栏")

	var before := state.current_hp
	state.set_hp(state.current_hp + def.out_of_combat_heal)
	var healed := state.current_hp - before
	discard(state, instance_id)
	return OperationResult.ok({"healed": healed})
