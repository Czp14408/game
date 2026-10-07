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


## 拾取：物品进入背包，触发入包自动合成（§8）。容量不足时整次回退，不掉包不丢物。
func pickup(state: RunState, it: ItemInstance) -> OperationResult:
	return auto_synthesize_into(state, it)


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


## 拖拽移动：把 instance_id 从来源栏移到目标栏的 target_index 位置，
## 其余物品按显示顺序自动让位（紧凑排列），不跨栏交换、不丢弃其他物品。
## 依据：游戏主界面与交互调整方案.md §7 物品拖拽表。
##
## 来源与目标：
##   src  ∈ {"bar","inv"} 且 dst ∈ {"bar","inv"}；相同即同栏重排，不同即跨栏移动（装备/卸下）。
## target_index 是目标栏里的格索引（按占格累加的绝对格位，非物品序号）。
##
## 原子性：先构造两份副本，校验最终容量与占用，全部通过才一次性提交；
## 任何失败（容量不足、物品不存在、不能装备）都不改变真实状态。
func move_item(state: RunState, instance_id: String, src: String, dst: String,
		target_index: int) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	if not state.is_held(instance_id):
		return OperationResult.fail("未持有该物品")
	var it := state.instance(instance_id)
	if src != "bar" and src != "inv":
		return OperationResult.fail("来源栏无效")
	if dst != "bar" and dst != "inv":
		return OperationResult.fail("目标栏无效")
	var src_arr := state.battle_bar if src == "bar" else state.inventory
	if not src_arr.has(it):
		return OperationResult.fail("物品不在指定来源栏")

	# 跨栏移动的装备约束：进入战斗栏必须可装备；恢复品不进战斗栏（服务层统一限制）。
	if src == "inv" and dst == "bar":
		var def := catalog.item(it.definition_id)
		if def == null or not def.equippable:
			return OperationResult.fail("该物品不能放入战斗栏")
		if def.category == ItemDef.CAT_CONSUMABLE:
			return OperationResult.fail("恢复品不进入战斗栏")

	# 构造目标序列：从目标栏移除「若已存在」的该实例，再在指定格位插入。
	var new_bar: Array = state.battle_bar.duplicate()
	var new_inv: Array = state.inventory.duplicate()
	new_bar.erase(it)
	new_inv.erase(it)

	var dst_arr: Array = new_bar if dst == "bar" else new_inv
	_insert_at(dst_arr, it, target_index)

	if not state.fits_after(new_bar, new_inv):
		return OperationResult.fail("目标栏空间不足")
	_commit(state, new_bar, new_inv)
	return OperationResult.ok({"instance_id": instance_id, "to": dst, "index": target_index})


## 把物品插入到按占格累加的绝对格位 target_index。
## 先按现有占格把目标栏展开成连续格，再在目标格位落位；其余物品在它之后顺延。
## 若 target_index 落在某件物品的中间，则落在该物品之前（即插到该物品起点处）。
func _insert_at(arr: Array, it: ItemInstance, target_index: int) -> void:
	# 计算每件现有物品的起始格
	var starts := PackedInt32Array()
	var cursor := 0
	for x in arr:
		starts.append(cursor)
		cursor += (x as ItemInstance).size(catalog)
	var span := maxi(it.size(catalog), 1)
	var insert := maxi(target_index, 0)
	# 找到第一个起始格 >= insert 的位置，插到它前面；若都在 insert 之前则插到末尾
	var pos := arr.size()
	for i in starts.size():
		if starts[i] >= insert:
			pos = i
			break
	arr.insert(pos, it)


## 入背包自动合成：物品进入背包后，检索背包内同名同品质候选，按显示顺序
## （数组从左到右即显示从左到右、从上到下）选择，连续升级，直到无候选或达钻石。
## 按连续合成后的最终占用校验容量；来源移除、合成、入包整次提交或整次回退。
## 依据：游戏主界面与交互调整方案.md §8 自动合成。
##
## 返回 data 含 produced_quality（最终品质，-1 表示未发生合成）、
## merged 次数、最终实例 id。钻石重复件作为独立物品接收，不叠加为一件。
func auto_synthesize_into(state: RunState, incoming: ItemInstance) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	var new_inv: Array = state.inventory.duplicate()
	var new_bar: Array = state.battle_bar.duplicate()

	# 先尝试在背包内连续合成：把 incoming 当作第一个「落袋」物品参与合成链。
	var work: ItemInstance = incoming
	var merged := 0
	var produced_quality := work.quality
	var guard := 0
	while guard < 64:
		guard += 1
		if work.quality >= ContentCatalog.MAX_QUALITY:
			break
		# 只有可装备物品参与自动合成：材料（CAT_MATERIAL）与恢复品（CAT_CONSUMABLE）
		# 直接入包不合成，避免把材料/消耗品当作合成素材被误吞。
		var wdef := catalog.item(work.definition_id)
		if wdef == null or not wdef.equippable:
			break
		# 在背包（new_inv）里找同名同品质候选，按数组顺序取第一个
		var cand: ItemInstance = null
		for other in new_inv:
			var o := other as ItemInstance
			if o.definition_id == work.definition_id and o.quality == work.quality:
				cand = o
				break
		if cand == null:
			break
		# 合成：消耗候选，产出高一品质；试炼成长加总继承
		var legacy := work.trial_growth + cand.trial_growth
		var produced := state.new_instance(work.definition_id, work.quality + 1, work.origin_node)
		produced.trial_growth = legacy
		new_inv.erase(cand)
		work = produced
		merged += 1
		produced_quality = work.quality

	# 合成链结束后把最终产物放入背包（保持紧凑顺序：追加到末尾）。
	new_inv.append(work)

	if not state.fits_after(new_bar, new_inv):
		return OperationResult.fail("背包空间不足")

	# 全部校验通过：提交。被合成的候选与来源实例统一置 LOC_NONE。
	var before: Array = state.inventory.duplicate()
	for o in before:
		if not new_inv.has(o):
			o.location = ItemInstance.LOC_NONE
	# incoming 若被合成链消耗（work != incoming），它本身也不在最终背包里，置 LOC_NONE；
	# 否则（无合成）它即最终产物，由 _commit 统一置 LOC_INVENTORY。
	if work != incoming:
		incoming.location = ItemInstance.LOC_NONE
	_commit(state, new_bar, new_inv)
	state.register_instance(work)
	return OperationResult.ok({
		"instance_id": work.instance_id,
		"produced_quality": produced_quality,
		"merged": merged,
		"changed": merged > 0,
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
