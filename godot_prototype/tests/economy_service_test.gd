class_name EconomyServiceTest
extends TestSuite
## M2 验收：正常购买/交换/失败操作正确，容量不足和重复操作不丢钱不复制物品。

var catalog: ContentCatalog
var rng: RandomService
var state: RunState
var economy: EconomyService
var inventory: InventoryService


func _init() -> void:
	suite_name = "M2 构筑与经济"


func run() -> void:
	catalog = ContentCatalog.load_default()
	_test_capacity()
	_test_equip_swap()
	_test_buy_sell()
	_test_refresh_and_lock()
	_test_synthesis()
	_test_drag_and_auto_synth()
	_test_skills()
	_test_consumable()
	_test_idempotency()
	_test_max_hp_trait()


func _setup(money: int = 200) -> void:
	rng = RandomService.create(99)
	state = RunState.create(catalog, rng)
	state.profession = &"warrior"
	state.bloodline = &"sturdy"
	state.apply_traits()
	state.money = money
	economy = EconomyService.new(catalog)
	economy.bind_rng(rng)
	inventory = economy.inventory


## 测试准备原语：直接把一件物品放进背包/战斗栏，不经过 pickup/自动合成。
## 这是「构造受控前置状态」的手段，语义与业务入口（pickup/buy）解耦，
## 避免自动合成在测试夹具阶段就悄悄合并同名物品、破坏后续断言。
func _hold(def_id: StringName, quality: int = 0, to_bar: bool = false) -> ItemInstance:
	var it := state.new_instance(def_id, quality)
	if to_bar:
		it.location = ItemInstance.LOC_BATTLE
		state.battle_bar.append(it)
	else:
		it.location = ItemInstance.LOC_INVENTORY
		state.inventory.append(it)
	return it


func _shop(items: Array, skills: Array = []) -> ShopState:
	var s := ShopState.new()
	s.shop_key = "03/gear_shop"
	s.shop_id = &"gear_shop"
	for entry in items:
		var slot := ShopState.Slot.new()
		var q: int = int(entry[1]) if entry.size() > 1 else 0
		slot.item = state.new_instance(entry[0], q)
		slot.item.location = ItemInstance.LOC_NONE
		slot.quality = q
		s.slots.append(slot)
	for entry_skill in skills:
		var sslot := ShopState.Slot.new()
		sslot.is_skill = true
		sslot.skill_id = entry_skill[0]
		sslot.quality = int(entry_skill[1]) if entry_skill.size() > 1 else 0
		s.slots.append(sslot)
	return s


# ---------------------------------------------------------------------------

func _test_capacity() -> void:
	_setup()
	# 战斗栏固定 10 格：2 + 2 + 3 + 3 = 10，再放 1 格物品失败
	_hold(&"long_blade", 0, true)
	_hold(&"ward_charm", 0, true)
	_hold(&"tower_shield", 0, true)
	_hold(&"heavy_hammer", 0, true)
	eq(state.bar_used(), 10, "战斗栏占用应为 10 格")
	var extra := _hold(&"short_blade")
	var r := inventory.equip(state, extra.instance_id)
	check(not r.success, "战斗栏满时应拒绝装备")
	eq(state.bar_used(), 10, "失败的装备不得改变占用")
	check(state.is_held(extra.instance_id), "失败的装备不得丢失物品")

	# 背包固定 10 点：材料逐件占 1 点
	_setup()
	for i in 9:
		_hold(&"scrap_material")
	eq(state.inventory_used(), 9, "背包占用应为 9 点")
	_hold(&"scrap_material")
	eq(state.inventory_used(), 10, "背包占用应为 10 点")
	var over := state.new_instance(&"scrap_material", 0)
	var r2 := inventory.pickup(state, over)
	check(not r2.success, "背包满时应拒绝拾取")

	# 交换不需要额外临时空格：卸下大件同时装上小件
	_setup()
	_hold(&"heavy_hammer", 0, true)
	var hammer := state.battle_bar[0]
	var small := _hold(&"short_blade")
	var r3 := inventory.unequip(state, hammer.instance_id)
	check(r3.success, "应先卸下大件腾出空间")
	var r4 := inventory.equip(state, small.instance_id)
	check(r4.success, "应能装上小件")


func _test_equip_swap() -> void:
	_setup()
	var blade := _hold(&"long_blade")
	eq(blade.location, ItemInstance.LOC_INVENTORY, "拾取后位置为背包")
	var r := inventory.equip(state, blade.instance_id)
	check(r.success, "装备应成功")
	eq(blade.location, ItemInstance.LOC_BATTLE, "装备后位置为战斗栏")
	eq(state.bar_used(), 2, "战斗栏占用 2 格")
	eq(state.inventory_used(), 0, "装备后不重复占用背包")
	var r2 := inventory.equip(state, blade.instance_id)
	check(not r2.success, "重复装备应失败")
	var r3 := inventory.unequip(state, blade.instance_id)
	check(r3.success, "卸下应成功")
	eq(state.inventory_used(), 2, "卸下后占用背包")
	eq(state.bar_used(), 0, "卸下后战斗栏为空")
	var r4 := inventory.unequip(state, blade.instance_id)
	check(not r4.success, "重复卸下应失败")


func _test_buy_sell() -> void:
	_setup(12)
	var shop := _shop([[&"ward_charm"], [&"short_blade"], [&"heavy_hammer"]])
	# 余额不足
	var r0 := economy.buy(state, shop, 2)
	check(not r0.success, "余额不足应拒绝购买重型装备（需要 14）")
	eq(state.money, 12, "失败不得扣币")
	# 正常购买 中型青铜 10
	var r1 := economy.buy(state, shop, 0)
	check(r1.success, "应能购买护身佩")
	eq(state.money, 2, "购买后余额")
	eq(state.inventory_used(), 2, "购买物进入背包")
	# 买走不补位 + 重复购买失败
	eq(shop.empty_slot_count(), 2, "买走后留下空位")
	var r2 := economy.buy(state, shop, 0)
	check(not r2.success, "同一商品位不能重复购买")
	eq(state.money, 2, "重复购买不得扣币")
	# 数量正确：不复制物品
	var count := 0
	for it in state.all_instances():
		if it.definition_id == &"ward_charm" and state.is_held(it.instance_id):
			count += 1
	eq(count, 1, "购买后应只持有一件")

	# 出售：严格减半
	_setup(0)
	var mat := _hold(&"scrap_material")
	var r3 := economy.sell(state, mat.instance_id, "")
	check(not r3.success, "商店外不能出售")
	var r4 := economy.sell(state, mat.instance_id, "03/gear_shop")
	check(r4.success, "在商店应能出售材料")
	eq(state.money, 4, "材料出售价")
	var blade := _hold(&"long_blade")
	economy.sell(state, blade.instance_id, "03/gear_shop")
	eq(state.money, 4 + 5, "中型青铜装备回收 5")
	var hammer := _hold(&"heavy_hammer")
	economy.sell(state, hammer.instance_id, "03/gear_shop")
	eq(state.money, 9 + 7, "大型青铜装备回收 7")
	check(not state.is_held(mat.instance_id), "出售后不再持有该实例")
	var r5 := economy.sell(state, mat.instance_id, "03/gear_shop")
	check(not r5.success, "重复出售应失败")

	# 技能不能出售
	_setup(0)
	economy.learn_skill(state, &"ever_stronger", 0)
	var skill_instances := 0
	for it in state.all_instances():
		if state.is_held(it.instance_id):
			skill_instances += 1
	eq(skill_instances, 0, "技能不生成可携带载体")
	eq(PriceTable.skill_sell_price(0), 0, "技能出售价为 0")


func _test_refresh_and_lock() -> void:
	_setup(50)
	var ns := state.node_state("03")
	var shop := economy.shops.state_for(state, "03", &"gear_shop")
	check(shop != null, "应能生成商店库存")
	eq(shop.slots.size(), 4, "每店 4 件商品")
	var before: Array = []
	for s in shop.slots:
		before.append(s.item.definition_id if not s.is_skill else s.skill_id)

	# 重开界面不免费刷新：同一 shop_id 返回同一库存
	var again := economy.shops.state_for(state, "03", &"gear_shop")
	check(again == shop, "重访应返回同一库存对象")

	# 锁定后不能刷新
	var lr := economy.set_lock(state, shop, true)
	check(lr.success, "应能锁定")
	var rr := economy.refresh(state, shop)
	check(not rr.success, "锁定后刷新应失败")
	eq(state.money, 50, "失败刷新不得扣币")
	economy.set_lock(state, shop, false)
	var rr2 := economy.refresh(state, shop)
	check(rr2.success, "解锁后刷新应成功")
	eq(state.money, 47, "刷新扣 3")
	var after: ShopState = economy.shops.state_for(state, "03", &"gear_shop")
	eq(after.refresh_serial, 1, "刷新序号递增")
	eq(after.slots.size(), 4, "刷新后仍为整批 4 件")

	# 品质概率：85% 青铜 / 15% 白银，不出现黄金与钻石
	var bronze := 0
	var silver := 0
	var higher := 0
	var rng2 := RandomService.create(4242)
	economy.bind_rng(rng2)
	var stock := economy.shops.state_for(state, "04", &"gear_shop")
	for slot in stock.slots:
		if slot.quality == 0:
			bronze += 1
		elif slot.quality == 1:
			silver += 1
		else:
			higher += 1
	eq(higher, 0, "第一阶段不应出现黄金或钻石商品")
	check(bronze + silver == 4, "商品品质应落在青铜或白银")

	# 多家店独立库存
	var weapon_shop := economy.shops.state_for(state, "03", &"weapon_shop")
	check(weapon_shop != shop, "同节点多店应有独立库存")
	var clinic := economy.shops.state_for(state, "03", &"clinic")
	check(clinic != shop, "医馆应有独立库存")


func _test_synthesis() -> void:
	_setup()
	var a := _hold(&"short_blade")
	var b := _hold(&"short_blade")
	a.trial_growth = 1.0
	b.trial_growth = 2.0
	var r := inventory.synthesize(state, a.instance_id, b.instance_id)
	check(r.success, "同名同品质应能合成")
	eq(int(r.data["quality"]), 1, "合成后品质提升一档")
	near(float(r.data["trial_growth"]), 3.0, 0.001, "本次试炼成长加总继承")
	check(not state.is_held(a.instance_id), "原实例应被消耗")
	check(not state.is_held(b.instance_id), "原实例应被消耗")
	var produced := state.instance(str(r.data["produced"]))
	eq(produced.definition_id, &"short_blade", "产物为同名物品")
	eq(PriceTable.item_base_price(catalog.item(&"short_blade"), produced.quality), 10, "产物按新档位计价")

	# 不同名 / 不同品质 / 钻石
	var c := _hold(&"long_blade")
	var d := _hold(&"short_blade")
	var r2 := inventory.synthesize(state, c.instance_id, d.instance_id)
	check(not r2.success, "不同名不能合成")
	var e := _hold(&"long_blade", 1)
	var r3 := inventory.synthesize(state, c.instance_id, e.instance_id)
	check(not r3.success, "不同品质不能合成")
	var dia := _hold(&"short_blade", 3)
	var dia2 := _hold(&"short_blade", 3)
	var r4 := inventory.synthesize(state, dia.instance_id, dia2.instance_id)
	check(not r4.success, "钻石不再升档")

	# 购买重复件再合成出售不能赚钱
	_setup(0)
	var x := _hold(&"short_blade")
	var y := _hold(&"short_blade")
	inventory.synthesize(state, x.instance_id, y.instance_id)
	var target: ItemInstance = null
	for it in state.all_instances():
		if state.is_held(it.instance_id) and it.definition_id == &"short_blade":
			target = it
	check(target != null, "应找到合成产物")
	economy.sell(state, target.instance_id, "03/gear_shop")
	check(state.money < 12, "两件青铜(12)合成后出售(5)不能赚钱")
	# 全部物品各档位均不可通过合成套利
	for id in catalog.all_item_ids():
		var def := catalog.item(id)
		for q in range(ContentCatalog.MAX_QUALITY):
			check(not PriceTable.synthesis_is_profitable(def, q), "%s 第 %d 档不应可套利" % [id, q])


## 拖拽移动与入背包自动合成（v0.5/v0.6/v0.7）。
## 依据：游戏主界面与交互调整方案.md §7 拖拽表、§8 自动合成。
func _test_drag_and_auto_synth() -> void:
	# --- 拖拽同栏重排：自动让位，不改变占用 ---
	_setup()
	var a := _hold(&"short_blade")       # 1 格
	var b := _hold(&"long_blade")        # 2 格
	var c := _hold(&"ward_charm")        # 2 格
	eq(state.inventory_used(), 5, "背包占用 5 点")
	# 把 a 从第 0 格移到第 3 格之后（重排顺序）
	var r := inventory.move_item(state, a.instance_id, "inv", "inv", 3)
	check(r.success, "同栏拖拽重排应成功")
	eq(state.inventory_used(), 5, "重排不改变占用")
	check(state.is_held(a.instance_id), "重排后物品仍持有")

	# --- 跨栏移动（装备）：背包→战斗栏 ---
	_setup()
	var blade := _hold(&"long_blade")   # 2 格，可装备
	var r2 := inventory.move_item(state, blade.instance_id, "inv", "bar", 0)
	check(r2.success, "背包→战斗栏装备应成功")
	eq(blade.location, ItemInstance.LOC_BATTLE, "装备后进入战斗栏")
	eq(state.bar_used(), 2, "战斗栏占用 2 格")
	eq(state.inventory_used(), 0, "装备后背包为空")

	# --- 跨栏移动（卸下）：战斗栏→背包 ---
	var r3 := inventory.move_item(state, blade.instance_id, "bar", "inv", 0)
	check(r3.success, "战斗栏→背包卸下应成功")
	eq(blade.location, ItemInstance.LOC_INVENTORY, "卸下后回到背包")

	# --- 容量不足整次回退 ---
	_setup()
	for i in 10:
		_hold(&"scrap_material")          # 背包占满 10 点
	eq(state.inventory_used(), 10, "背包已满")
	var big := state.new_instance(&"heavy_hammer", 0)  # 3 格
	var r4 := inventory.move_item(state, "", "inv", "inv", 0)
	check(not r4.success, "空实例 ID 应失败")
	# 尝试把背包里的材料拖到战斗栏（材料不可装备）应失败
	var mat := state.inventory[0]
	var r5 := inventory.move_item(state, mat.instance_id, "inv", "bar", 0)
	check(not r5.success, "材料不能放入战斗栏")
	check(state.is_held(mat.instance_id), "失败不丢失物品")
	eq(state.inventory_used(), 10, "失败不改变占用")

	# --- 入背包自动合成：连续升级 + 最终容量校验 ---
	_setup()
	# 直接往背包放两件同名同品质青铜（绕过 pickup/自动合成，构造受控前置状态），
	# 再入包一件同名青铜 → 两件青铜合成一件白银，再与第三件？连续升级。
	var x := state.new_instance(&"short_blade", 0)
	var y := state.new_instance(&"short_blade", 0)
	x.location = ItemInstance.LOC_INVENTORY
	y.location = ItemInstance.LOC_INVENTORY
	state.inventory.append(x)
	state.inventory.append(y)
	eq(state.inventory_used(), 2, "背包现有 2 件青铜短刀")
	var incoming := state.new_instance(&"short_blade", 0)
	incoming.location = ItemInstance.LOC_NONE
	var sr := inventory.auto_synthesize_into(state, incoming)
	check(sr.success, "入包自动合成应成功")
	check(int(sr.data.get("merged", 0)) >= 1, "应发生合成（merged=%d）" % int(sr.data.get("merged", 0)))
	# 两件青铜（x,y）+ 新青铜 incoming → 合成一件白银（消耗 x + incoming），剩 y 青铜 + 新白银
	# 最终：背包里 short_blade 青铜 1 件 + 白银 1 件
	var bronze_count := 0
	var silver_count := 0
	for it in state.inventory:
		if it.definition_id == &"short_blade" and it.quality == 0:
			bronze_count += 1
		elif it.definition_id == &"short_blade" and it.quality == 1:
			silver_count += 1
	check(bronze_count == 1 and silver_count == 1, "合成后剩 1 青铜 + 1 白银（实 %d/%d）" % [bronze_count, silver_count])

	# --- 钻石重复件作为独立物品接收，不叠加 ---
	_setup()
	var d1 := _hold(&"short_blade", 3)
	var d2 := state.new_instance(&"short_blade", 3)
	d2.location = ItemInstance.LOC_NONE
	var sr2 := inventory.auto_synthesize_into(state, d2)
	check(sr2.success, "钻石重复件应作为独立物品接收")
	eq(int(sr2.data.get("merged", 0)), 0, "钻石不再合成")
	var diamond_count := 0
	for it in state.inventory:
		if it.definition_id == &"short_blade" and it.quality == 3:
			diamond_count += 1
	eq(diamond_count, 2, "钻石重复件不叠加为一件")


func _test_skills() -> void:
	_setup(100)
	# 购买后立即学习，不进入背包
	var shop := _shop([], [[&"ever_stronger", 0]])
	var r := economy.buy(state, shop, 0)
	check(r.success, "应能购买技能")
	eq(state.money, 88, "青铜技能价格 12")
	eq(state.skill_quality(&"ever_stronger"), 0, "技能已学习")
	eq(state.inventory_used(), 0, "技能不占背包")

	# 同名同品质购买 → 合成提升一级
	var shop2 := _shop([], [[&"ever_stronger", 0]])
	economy.buy(state, shop2, 0)
	eq(state.skill_quality(&"ever_stronger"), 1, "同名同品质技能应合成提升")
	eq(state.skills.size(), 1, "技能效果不重复叠加")
	# 低品质不降级
	var r2 := economy.learn_skill(state, &"ever_stronger", 0)
	check(not r2.success, "低品质同名技能不应降级")
	eq(state.skill_quality(&"ever_stronger"), 1, "品质保持不变")
	# 高品质替换并保留本次试炼成长
	state.skills[&"ever_stronger"].trial_growth = 2.0
	var r3 := economy.learn_skill(state, &"ever_stronger", 2)
	check(r3.success, "高品质应替换低品质")
	eq(state.skill_quality(&"ever_stronger"), 2, "品质提升")
	near(state.skills[&"ever_stronger"].trial_growth, 2.0, 0.001, "替换保留本次试炼成长")
	# 钻石重复不再提升
	var d1 := economy.learn_skill(state, &"ever_stronger", 3)
	check(d1.success, "应能替换为钻石")
	var d2 := economy.learn_skill(state, &"ever_stronger", 3)
	check(not d2.success, "钻石重复不应继续提升")


func _test_consumable() -> void:
	_setup()
	var draught := _hold(&"recovery_draught")
	# 满血时禁用
	var r := inventory.use_recovery(state, draught.instance_id)
	check(not r.success, "满血时恢复品按钮应禁用")
	client_hp_drop()
	var r2 := inventory.use_recovery(state, draught.instance_id)
	check(r2.success, "非满血应能使用恢复品")
	eq(state.current_hp, 80.0, "从 50 恢复 30 后为 80")
	check(not state.is_held(draught.instance_id), "使用后消耗一个实例")
	# 恢复不超过上限
	state.set_hp(90.0)
	var d2 := _hold(&"recovery_draught")
	inventory.use_recovery(state, d2.instance_id)
	eq(state.current_hp, state.max_hp, "恢复量不超过最大生命")


func client_hp_drop() -> void:
	state.set_hp(50.0)


func _test_idempotency() -> void:
	_setup(100)
	var shop := _shop([[&"short_blade"]])
	var r1 := economy.buy(state, shop, 0)
	var r2 := economy.buy(state, shop, 0)
	check(r1.success and not r2.success, "重复点击购买应幂等")
	eq(state.money, 94, "重复点击不得重复扣币")
	var held := 0
	for it in state.all_instances():
		if state.is_held(it.instance_id):
			held += 1
	eq(held, 1, "重复点击不得复制物品")


func _test_max_hp_trait() -> void:
	# 职业与血统的 max_hp_flat 都要生效（回归：apply_traits 曾只读 bloodline，
	# 职业侧的同名效果被静默忽略）。现有内容里只有血统「强健」带该效果，
	# 因此注入一份带 max_hp_flat 的职业来覆盖职业侧这条路径。
	var cat := ContentCatalog.load_default()
	var fake := TraitDef.new()
	fake.trait_id = &"__test_prof_maxhp"
	fake.display_name = "测试职业"
	fake.kind = TraitDef.KIND_PROFESSION
	fake.effect_type = TraitDef.EFFECT_MAX_HP_FLAT
	fake.effect_amount = 30.0
	cat.traits[fake.trait_id] = fake

	var both := RunState.create(cat, RandomService.create(7))
	both.profession = &"__test_prof_maxhp"
	both.bloodline = &"sturdy"
	both.apply_traits()
	eq(both.max_hp, 150.0, "职业 max_hp_flat 30 + 血统 20 + 基础 100 = 150")
	eq(both.current_hp, 150.0, "起始生命随最大生命")

	var blood_only := RunState.create(cat, RandomService.create(7))
	blood_only.profession = &"warrior"
	blood_only.bloodline = &"sturdy"
	blood_only.apply_traits()
	eq(blood_only.max_hp, 120.0, "武者 + 强健：基础 100 + 血统 20 = 120（与既有口径一致）")
