class_name WorldFlowTest
extends TestSuite
## M3 验收：新节点扣费、免费重访、守路、取消挑战、资源保留成立；
## 三条固定输入路线与《游戏最小战斗与经济方案.md》第 7 节及技术方案第 16 节一致。
##
## 说明：三条路线使用显式固定输入（掉落序列、商店库存、阶段对手），
## 它们是验证样本，不是玩家随机结果的保底，也不能据此估计总体通关率。

var catalog: ContentCatalog


func _init() -> void:
	suite_name = "M3 世界流程与三路线"


func run() -> void:
	catalog = ContentCatalog.load_default()
	_test_node_fees_and_guard()
	_test_quests()
	_test_container_and_state_keep()
	_test_route_normal()
	_test_route_low()
	_test_route_failure()
	_test_stage_opponent_fixed()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _new_run(seed_value: int, drops: Dictionary, stage: Dictionary) -> RunController:
	var ctrl := RunController.new()
	ctrl.catalog = catalog
	ctrl.start_new_app(seed_value)
	ctrl.new_trial(&"warrior", &"sturdy", seed_value)
	ctrl.encounters.drop_override = drops
	ctrl.encounters.stage_override = stage
	return ctrl


func _fix_shop(ctrl: RunController, node_id: String, shop_id: StringName, ids: Array, skills: Array = []) -> void:
	var s := ShopState.new()
	s.shop_key = "%s/%s" % [node_id, shop_id]
	s.shop_id = shop_id
	for entry in ids:
		var slot := ShopState.Slot.new()
		var q: int = int(entry[1]) if entry.size() > 1 else 0
		slot.item = ctrl.state.new_instance(entry[0], q)
		slot.item.location = ItemInstance.LOC_NONE
		slot.quality = q
		s.slots.append(slot)
	for entry2 in skills:
		var sslot := ShopState.Slot.new()
		sslot.is_skill = true
		sslot.skill_id = entry2[0]
		sslot.quality = int(entry2[1]) if entry2.size() > 1 else 0
		s.slots.append(sslot)
	ctrl.state.node_state(node_id).shops[shop_id] = s


func _slot_of(shop: ShopState, def_id: StringName) -> int:
	for i in shop.slots.size():
		var slot: ShopState.Slot = shop.slots[i]
		if slot.is_skill:
			if slot.skill_id == def_id:
				return i
		elif slot.item != null and slot.item.definition_id == def_id:
			return i
	return -1


func _buy(ctrl: RunController, node_id: String, shop_id: StringName, def_id: StringName) -> OperationResult:
	ctrl.open_shop("%s/%s" % [node_id, shop_id])
	var shop := ctrl.current_shop()
	var idx := _slot_of(shop, def_id)
	if idx < 0:
		return OperationResult.fail("固定库存里没有 %s" % def_id)
	return ctrl.buy_slot(idx)


func _held_instance(ctrl: RunController, def_id: StringName, quality: int = -1) -> ItemInstance:
	for it in ctrl.state.all_instances():
		if it.definition_id != def_id:
			continue
		if quality >= 0 and it.quality != quality:
			continue
		if ctrl.state.is_held(it.instance_id):
			return it
	return null


func _equip(ctrl: RunController, def_id: StringName, quality: int = -1) -> void:
	var it := _held_instance(ctrl, def_id, quality)
	if it == null:
		check(false, "应持有 %s 以便装备" % def_id)
		return
	var r := ctrl.equip(it.instance_id)
	check(r.success, "装备 %s 失败：%s" % [def_id, r.reason])


func _sell_all(ctrl: RunController, def_id: StringName, node_id: String = "03", shop_id: StringName = &"gear_shop") -> int:
	var n := 0
	while true:
		var it := _held_instance(ctrl, def_id)
		if it == null:
			break
		ctrl.open_shop("%s/%s" % [node_id, shop_id])
		var r := ctrl.sell(it.instance_id)
		if not r.success:
			break
		n += 1
	return n


## 按数量出售（回放只卖与文档步表一致的数量）
func _sell_n(ctrl: RunController, def_id: StringName, n: int, node_id: String = "03", shop_id: StringName = &"gear_shop") -> int:
	var sold := 0
	for i in n:
		var it := _held_instance(ctrl, def_id)
		if it == null:
			break
		ctrl.open_shop("%s/%s" % [node_id, shop_id])
		if ctrl.sell(it.instance_id).success:
			sold += 1
	return sold


func _equipped_instance(ctrl: RunController, def_id: StringName) -> ItemInstance:
	for it in ctrl.state.battle_bar:
		if it.definition_id == def_id:
			return it
	return null


func _held_other(ctrl: RunController, def_id: StringName, quality: int, exclude_id: String) -> ItemInstance:
	for it in ctrl.state.all_instances():
		if it.definition_id != def_id or it.instance_id == exclude_id:
			continue
		if quality >= 0 and it.quality != quality:
			continue
		if ctrl.state.is_held(it.instance_id):
			return it
	return null


func _fight(ctrl: RunController, node_id: String, template_id: StringName, expect_win: bool = true) -> BattleResult:
	var key := ""
	for k in ctrl.node_enemy_keys():
		var es := ctrl.encounters.ensure(ctrl.state, node_id, k)
		if es.enemy_template_id == template_id and not es.defeated:
			key = k
			break
	if key == "":
		check(false, "%s 号节点找不到可挑战的 %s" % [node_id, template_id])
		return null
	ctrl.open_pre_battle(key)
	ctrl.confirm_battle()
	ctrl.active_engine.run_all()
	var result: BattleResult = ctrl.active_engine.result()
	ctrl.settle_battle(ctrl.active_engine)
	if expect_win and not result.winner_is_player():
		check(false, "%s 号节点 %s 应获胜，实际 %s" % [node_id, template_id, result.outcome_text()])
	return result


func _grant(ctrl: RunController, def_id: StringName, to_bar: bool = false, quality: int = 0) -> ItemInstance:
	var it := ctrl.state.new_instance(def_id, quality)
	var r := ctrl.inventory.pickup(ctrl.state, it)
	check(r.success, "测试准备：拾取 %s" % def_id)
	if to_bar:
		var er := ctrl.inventory.equip(ctrl.state, it.instance_id)
		check(er.success, "测试准备：装备 %s" % def_id)
	return it


func _go(ctrl: RunController, path: Array) -> void:
	for node_id in path:
		var r := ctrl.travel_to(node_id)
		check(r.success, "进入 %s 失败：%s" % [node_id, r.reason])


# ---------------------------------------------------------------------------
# 节点费用、守路与重访
# ---------------------------------------------------------------------------

func _test_node_fees_and_guard() -> void:
	var ctrl := _new_run(11, {}, {})
	eq(ctrl.state.money, 30, "起始资金 30")
	eq(ctrl.state.current_node_id, "01", "免费入口节点")
	eq(ctrl.state.node_state("01").fee_amount, 0, "入口不收费")
	eq(ctrl.state.paid_node_count, 0, "付费节点计数为 0")

	# 第一个新节点 2，第二个 3，依次递增
	_go(ctrl, ["02"])
	eq(ctrl.state.money, 28, "第一个新节点费用 2")
	eq(ctrl.state.paid_node_count, 1, "付费节点计数 1")
	eq(ctrl.world.next_fee_preview(ctrl.state), 3, "下一新节点费用预览 3")

	# 免费重访不增加计数
	_go(ctrl, ["01"])
	eq(ctrl.state.money, 28, "重访入口免费")
	eq(ctrl.state.paid_node_count, 1, "重访不增加计数")

	_go(ctrl, ["02", "03"])
	eq(ctrl.state.money, 25, "第二个新节点费用 3")
	eq(ctrl.state.paid_node_count, 2, "付费节点计数 2")

	# 从大地图选择目的节点不能绕过守路限制
	var blocked := ctrl.world.can_travel(ctrl.state, "11")
	_go(ctrl, ["05", "06", "08"])
	eq(ctrl.state.current_node_id, "08", "应到达山口")
	var r := ctrl.world.can_travel(ctrl.state, "11")
	check(not r.success, "守路者未击败时 08—11 不可通行：%s" % r.reason)
	var r2 := ctrl.travel_to("11")
	check(not r2.success, "从大地图选择目的节点也不能绕过守路限制")
	check(ctrl.state.node_state("08").guard_revealed.size() >= 1, "发现守路条件后应显示原因")
	# 其他连接仍可使用
	eq(ctrl.state.current_node_id, "08", "被拦截后仍停留在当前节点")
	var r3 := ctrl.world.can_travel(ctrl.state, "13")
	check(r3.success, "其他连接仍可使用（08—13）")

	# 取消挑战：屏蔽自动弹窗
	ctrl.open_pre_battle("08>mountain_guard#guard")
	ctrl.cancel_battle()
	var es := ctrl.state.node_state("08").encounter("08>mountain_guard#guard")
	check(es.auto_prompt_suppressed, "取消后应屏蔽该敌人的自动弹窗")
	ctrl.open_pre_battle("08>mountain_guard#guard")
	ctrl.release_suppression()
	check(not es.auto_prompt_suppressed, "离开接触区域后应解除屏蔽")

	# 击败守路者后连接开放
	_grant(ctrl, &"ward_charm", true)
	_grant(ctrl, &"short_blade", true)
	ctrl.open_pre_battle("08>mountain_guard#guard")
	ctrl.confirm_battle()
	ctrl.active_engine.run_all()
	ctrl.settle_battle(ctrl.active_engine)
	var r4 := ctrl.world.can_travel(ctrl.state, "11")
	check(r4.success, "击败守路者后连接应开放")

	# 战败返回当前节点入口、无奖励、不额外收节点费
	var before := ctrl.state.money
	ctrl.open_pre_battle("08>bandit#0")
	ctrl.confirm_battle()
	ctrl.active_engine.run_all()
	var lost: BattleResult = ctrl.active_engine.result()
	if not lost.winner_is_player():
		eq(ctrl.state.current_node_id, "08", "战败后仍停留在当前节点")
		eq(ctrl.state.current_hp, ctrl.state.max_hp, "战败后恢复至最大生命")
	eq(ctrl.state.money, before, "战败不产生奖励也不扣节点费")


func _test_quests() -> void:
	var ctrl := _new_run(21, {"02": "material", "05": "material"}, {})
	# 主线自动接取，但奖励不提前发放
	eq(ctrl.state.quest_state(&"main_kill_chief").status, QuestState.STATUS_ACCEPTED, "主线应已接取")
	check(not ctrl.state.main_completed, "主线未完成")
	var rr := ctrl.world.can_return(ctrl.state)
	check(not rr.success, "主线未完成时不能回归")

	# 支线追认：先接取，再完成目标
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
	eq(ctrl.state.quest_state(&"side_road_bandit").status, QuestState.STATUS_ACCEPTED, "路匪支线应已接取")
	# 先击杀 05 的路匪，再接取挑战支线（追认接取前已完成的目标）
	_go(ctrl, ["02", "03", "05"])
	_fight(ctrl, "05", &"bandit")
	eq(ctrl.state.quest_state(&"side_road_bandit").status, QuestState.STATUS_COMPLETED, "击杀路匪后应为待领奖")
	var money_before := ctrl.state.money
	var claim := ctrl.quests.claim(ctrl.state, &"side_road_bandit")
	check(not claim.success, "不在 01 号节点不能领取委托奖励")
	_go(ctrl, ["03", "01"])
	var ok_claim := ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
	check(ok_claim.success, "回到 01 应能领取路匪支线奖励")
	eq(ctrl.state.money - money_before, 6, "路匪支线奖励 6")
	var again := ctrl.quests.claim(ctrl.state, &"side_road_bandit")
	check(not again.success, "每项奖励最多领取一次")
	eq(ctrl.state.money - money_before, 6, "重复领奖不得加钱")

	# 挑战支线：先接取，再击败目标，现场结算
	_go(ctrl, ["02"])
	ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)
	eq(ctrl.state.quest_state(&"side_challenge").status, QuestState.STATUS_ACCEPTED, "挑战支线应先进入进行中")
	var money2 := ctrl.state.money
	_fight(ctrl, "02", &"bandit")
	eq(ctrl.state.quest_state(&"side_challenge").status, QuestState.STATUS_CLAIMED, "武馆挑战完成时自动结算")
	eq(ctrl.state.money - money2, 12, "挑战支线战斗 6 + 支线奖励 6")


func _test_container_and_state_keep() -> void:
	var ctrl := _new_run(31, {"05": "material"}, {})
	_go(ctrl, ["02", "03", "05"])
	var ns := ctrl.state.node_state("05")
	check(ns.entered, "节点应标记为已进入")
	# 容器只生成一次结果
	ns.containers["05#c0"] = {"opened": true, "table": &"material_small", "drops": []}
	_go(ctrl, ["03", "05"])
	check(bool(ns.containers["05#c0"]["opened"]), "重访应保留容器已开启状态")
	eq(ns.containers["05#c0"]["drops"].size(), 0, "重访不得重复抽取容器内容")
	# 敌人已击败不复活
	_fight(ctrl, "05", &"bandit")
	var defeated_count := 0
	for k in ns.encounters.keys():
		if (ns.encounters[k] as EncounterState).defeated:
			defeated_count += 1
	eq(defeated_count, 1, "应有一个已击败遭遇")
	_go(ctrl, ["03", "05"])
	var still := 0
	for k in ns.encounters.keys():
		if (ns.encounters[k] as EncounterState).defeated:
			still += 1
	eq(still, defeated_count, "重访后已击败敌人不复活")
	# 商店库存延续
	var shop := ctrl.economy.shops.state_for(ctrl.state, "03", &"gear_shop")
	var slot0: ShopState.Slot = shop.slots[0]
	slot0.purchased = true
	var shop2 := ctrl.economy.shops.state_for(ctrl.state, "03", &"gear_shop")
	check(shop2.slots[0].purchased, "重访商店应保留购买留下的空位")


# ---------------------------------------------------------------------------
# 三条固定输入路线
# ---------------------------------------------------------------------------

func _route_shops(ctrl: RunController) -> void:
	# 03 号节点的固定验证库存（显式测试输入）
	_fix_shop(ctrl, "03", &"gear_shop", [[&"ward_charm"], [&"short_blade"], [&"rejuvenator"], [&"fire_oil"]])
	_fix_shop(ctrl, "03", &"clinic", [[&"recovery_draught"], [&"rejuvenator"]])
	_fix_shop(ctrl, "03", &"weapon_shop", [])


func _deity_store(ctrl: RunController) -> void:
	_fix_shop(ctrl, "__deity__", &"deity_mixed", [[&"short_blade"], [&"rejuvenator"], [&"poison_needle"]],
		[[&"ever_stronger", 0]])


func _test_route_normal() -> void:
	var ctrl := _new_run(20261007, {
		"02": "bandit_knife", "05": "material", "08": "ward_charm",
		"12": "long_blade", "15": "heavy_hammer",
	}, {})
	_route_shops(ctrl)
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
	eq(int(ctrl.state.current_hp), 120, "开局生命 120")

	# 01 → 02
	_go(ctrl, ["02"])
	var r02 := _fight(ctrl, "02", &"bandit")
	eq(int(r02.player_hp), 80, "02 战后生命 80")
	ctrl.pickup_drops()
	ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)
	eq(ctrl.state.money, 40, "02 后现金 40（含挑战支线 6）")
	eq(ctrl.state.current_hp, 80.0, "02 后生命 80")

	# 03：出售短刀、购买护身佩
	_go(ctrl, ["03"])
	_sell_all(ctrl, &"bandit_knife")
	var buy_ward := _buy(ctrl, "03", &"gear_shop", &"ward_charm")
	check(buy_ward.success, "应能买到护身佩：%s" % buy_ward.reason)
	_equip(ctrl, &"ward_charm")
	eq(ctrl.state.money, 30, "03 购护身佩后现金 30")

	# 05
	_go(ctrl, ["05"])
	var r05 := _fight(ctrl, "05", &"bandit")
	eq(int(r05.player_hp), 72, "05 战后生命 72")
	ctrl.pickup_drops()

	# 重访 03：出售材料，买短刃与恢复品并使用
	_go(ctrl, ["03"])
	eq(_sell_all(ctrl, &"scrap_material"), 1, "应出售一份材料")
	var buy_short := _buy(ctrl, "03", &"gear_shop", &"short_blade")
	check(buy_short.success, "应能买到短刃")
	_equip(ctrl, &"short_blade")
	var buy_draught := _buy(ctrl, "03", &"clinic", &"recovery_draught")
	check(buy_draught.success, "应能买到恢复品")
	var draught := _held_instance(ctrl, &"recovery_draught")
	var used := ctrl.use_recovery(draught.instance_id)
	check(used.success, "应能使用恢复品：%s" % used.reason)
	eq(ctrl.state.current_hp, 102.0, "使用恢复品后生命 102")

	# 回 01 领取路匪支线奖励
	_go(ctrl, ["01"])
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

	# 06
	_go(ctrl, ["03", "05", "06"])
	ctrl.talk_to(NodeDef.NPC_INTEL_TARGET)
	check(ctrl.state.known_intel.has("chief_node"), "应获得头子准确节点情报")
	check(ctrl.is_main_target_known(), "主线目标位置应为已知")

	# 08：守路者，掉落护身佩并与已买青铜件合成白银
	_go(ctrl, ["08"])
	var r08 := _fight(ctrl, "08", &"mountain_guard")
	eq(int(r08.player_hp), 102, "08 战后生命 102")
	ctrl.pickup_drops()
	var ward_equipped := ctrl.state.battle_bar[1]
	var ward_bronze := _held_other(ctrl, &"ward_charm", 0, ward_equipped.instance_id)
	check(ward_bronze != null, "应持有两件青铜护身佩待合成")
	var syn := ctrl.synthesize(ward_equipped.instance_id, ward_bronze.instance_id)
	check(syn.success, "护身佩应能合成：%s" % syn.reason)
	var ward_after := _equipped_instance(ctrl, &"ward_charm")
	check(ward_after != null, "合成产物应留在战斗栏")
	eq(ward_after.quality, 1, "装备中的护身佩应提升为白银")

	# 11 → 12
	_go(ctrl, ["11", "12"])
	var r12 := _fight(ctrl, "12", &"camp_blade")
	eq(int(r12.player_hp), 102, "12 战后生命 102")
	eq(r12.time_seconds, 8.0, "12 耗时 8 秒")
	ctrl.pickup_drops()
	# 12 掉落长刀，与起始长刀合成白银
	var blade_equipped := _equipped_instance(ctrl, &"long_blade")
	var blade_drop := _held_other(ctrl, &"long_blade", 0, blade_equipped.instance_id if blade_equipped != null else "")
	check(blade_drop != null and blade_equipped != null, "应持有两件青铜长刀待合成")
	var syn2 := ctrl.synthesize(blade_equipped.instance_id, blade_drop.instance_id)
	check(syn2.success, "长刀应能合成：%s" % syn2.reason)

	# 15：主线
	_go(ctrl, ["15"])
	var r15 := _fight(ctrl, "15", &"bandit_chief")
	eq(int(r15.player_hp), 102, "15 战后生命 102")
	eq(r15.time_seconds, 12.0, "15 耗时 12 秒")
	ctrl.pickup_drops()
	check(ctrl.state.main_completed, "击杀头子应完成主线")
	eq(ctrl.state.money, 37, "主线完成时现金 37（战斗 6 + 主线 24）")
	eq(ctrl.state.defeats, 0, "正常路线 0 次战败")

	# 主线后回归前再探索一个付费节点
	_go(ctrl, ["12", "11", "08", "06", "05", "03", "17"])
	eq(ctrl.state.paid_node_count, 9, "主线后仍按阶梯计费（第 9 个新节点）")
	eq(ctrl.state.money, 27, "进入 17 后现金 27")
	eq(ctrl.state.current_hp, 102.0, "回归前生命 102")

	# 回归与整备
	ctrl.return_to_deity()
	check(ctrl.state.returned_to_deity, "应已回归主神空间")
	ctrl.deity_heal()
	eq(ctrl.state.current_hp, 120.0, "主神治疗免费回满")
	eq(ctrl.state.money, 27, "免费治疗不扣币")
	check(ctrl.encounters.ensure_stage_opponent(ctrl.state).size() > 0, "应生成阶段对手")


func _test_route_low() -> void:
	# 全材料压力样本：五场均为材料
	var ctrl := _new_run(20261008, {
		"02": "material", "05": "material", "08": "material", "12": "material", "15": "material",
	}, {"template": &"damage_over_time", "extra": &"rejuvenator"})
	_route_shops(ctrl)
	_deity_store(ctrl)
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

	_go(ctrl, ["02"])
	eq(int(_fight(ctrl, "02", &"bandit").player_hp), 80, "全材料路线 02 后生命 80")
	ctrl.pickup_drops()
	ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)

	_go(ctrl, ["03"])
	var bw := _buy(ctrl, "03", &"gear_shop", &"ward_charm")
	check(bw.success, "应能买到护身佩")
	_equip(ctrl, &"ward_charm")

	_go(ctrl, ["05"])
	eq(int(_fight(ctrl, "05", &"bandit").player_hp), 72, "全材料路线 05 后生命 72")
	ctrl.pickup_drops()

	_go(ctrl, ["03"])
	var bs := _buy(ctrl, "03", &"gear_shop", &"short_blade")
	check(bs.success, "应能买到短刃")
	_equip(ctrl, &"short_blade")
	var bd := _buy(ctrl, "03", &"clinic", &"recovery_draught")
	check(bd.success, "应能买到恢复品")
	var dr := _held_instance(ctrl, &"recovery_draught")
	ctrl.use_recovery(dr.instance_id)
	eq(ctrl.state.current_hp, 102.0, "全材料路线使用恢复品后生命 102")

	_go(ctrl, ["01"])
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

	_go(ctrl, ["03", "05", "06", "08"])
	eq(int(_fight(ctrl, "08", &"mountain_guard").player_hp), 102, "全材料路线 08 后生命 102")
	ctrl.pickup_drops()

	_go(ctrl, ["11", "12"])
	var r12 := _fight(ctrl, "12", &"camp_blade")
	eq(r12.time_seconds, 8.0, "全材料路线 12 耗时 8 秒")
	ctrl.pickup_drops()

	_go(ctrl, ["15"])
	var r15 := _fight(ctrl, "15", &"bandit_chief")
	eq(r15.time_seconds, 14.0, "全材料路线头子耗时 14 秒")
	eq(int(r15.player_hp), 78, "全材料路线头子战后生命 78")
	ctrl.pickup_drops()
	check(ctrl.state.main_completed, "全材料路线应完成主线")

	# 回归：出售全部材料
	_go(ctrl, ["12", "11", "08", "06", "05", "03"])
	eq(_sell_all(ctrl, &"scrap_material", "03", &"clinic"), 5, "应出售五份材料（02/05/08/12/15 各一份）")
	ctrl.return_to_deity()
	ctrl.deity_heal()
	eq(ctrl.state.money, 50, "全材料路线回归资金 50")
	eq(ctrl.state.current_hp, 120.0, "回归治疗回满")

	# 先看清对手再补强：买青铜越战越勇
	var sk := _buy(ctrl, "__deity__", &"deity_mixed", &"ever_stronger")
	check(sk.success, "应能买到越战越勇：%s" % sk.reason)
	eq(ctrl.state.money, 38, "购买技能后余额 38")
	eq(ctrl.state.skill_quality(&"ever_stronger"), 0, "越战越勇应已学习")

	# 阶段对手：持续伤害＋治疗
	ctrl.confirm_stage_battle()
	ctrl.active_engine.run_all()
	var boss: BattleResult = ctrl.active_engine.result()
	check(boss.winner_is_player(), "补强后应击败阶段对手")
	eq(boss.time_seconds, 22.0, "阶段耗时 22 秒")
	eq(int(boss.player_hp), 60, "阶段战后生命 60")
	ctrl.settle_stage_battle(ctrl.active_engine)
	eq(ctrl.state.defeats, 0, "全材料路线 0 次战败")
	eq(ctrl.state.state, RunState.STATE_STAGE_COMPLETE, "应进入原型阶段完成")

	# 对照：不补强的同一固定配置只能打到第 30 秒
	var set_ := catalog.stage_set(&"stage_01")
	var equipment: Array = []
	for t in set_.templates:
		if t.template_id == &"damage_over_time":
			for g in t.equipment:
				equipment.append(g)
	equipment.append(GrantDef.item(&"rejuvenator", 0))
	var bare := _new_run(1, {}, {})
	var player := CombatEngine.build_actor(catalog, {
		"side": CombatActor.SIDE_PLAYER, "display_name": "玩家", "max_hp": 120.0, "hp": 120.0,
		"profession": &"warrior", "bloodline": &"sturdy",
		"items": [
			{"definition_id": &"long_blade", "quality": 0},
			{"definition_id": &"ward_charm", "quality": 0},
			{"definition_id": &"short_blade", "quality": 0},
		],
	})
	var opponent := CombatEngine.build_stage_opponent(catalog, set_, equipment, "持续伤害＋治疗")
	var eng := CombatEngine.new()
	eng.catalog = catalog
	eng.rng = bare.rng
	eng.begin(player, opponent, "bare_stage", "battle/bare_stage")
	var bare_result := eng.run_all()
	check(not bare_result.winner_is_player(), "未补强的青铜组合不应击败追加治疗的阶段对手")
	eq(bare_result.time_seconds, 30.0, "未补强时应打到第 30 秒")
	near(bare_result.enemy_hp, 13.0, 4.0, "未补强时对手剩余生命约 13")
	note("未补强阶段战对手剩余生命实测 %.1f（文档记录 13）" % bare_result.enemy_hp)


func _test_route_failure() -> void:
	var ctrl := _new_run(20261009, {
		"02": "material", "05": "material", "08": "material", "12": "material", "15": "material",
	}, {"template": &"damage_over_time", "extra": &"rejuvenator"})
	_route_shops(ctrl)
	_deity_store(ctrl)
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

	_go(ctrl, ["02"])
	eq(int(_fight(ctrl, "02", &"bandit").player_hp), 80, "战败路线 02 后生命 80")
	ctrl.pickup_drops()
	ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)

	_go(ctrl, ["03"])
	var bw := _buy(ctrl, "03", &"gear_shop", &"ward_charm")
	check(bw.success, "应能买到护身佩")
	_equip(ctrl, &"ward_charm")

	_go(ctrl, ["05"])
	eq(int(_fight(ctrl, "05", &"bandit").player_hp), 72, "战败路线 05 后生命 72")
	ctrl.pickup_drops()

	_go(ctrl, ["03"])
	var bd := _buy(ctrl, "03", &"clinic", &"recovery_draught")
	check(bd.success, "应能买到恢复品")
	_go(ctrl, ["01"])
	ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
	_go(ctrl, ["03", "05", "06", "08"])

	# 只用长刀＋护身佩打山口，跨过沙尘暴起点
	var r08 := _fight(ctrl, "08", &"mountain_guard")
	eq(r08.time_seconds, 33.0, "战败路线 08 耗时 33 秒")
	eq(int(r08.player_hp), 10, "战败路线 08 战后生命 10")
	ctrl.pickup_drops()
	var dr := _held_instance(ctrl, &"recovery_draught")
	check(dr != null, "应还持有恢复品")
	ctrl.use_recovery(dr.instance_id)
	eq(ctrl.state.current_hp, 40.0, "使用恢复品后生命 40")

	_go(ctrl, ["11", "12"])
	var r12 := _fight(ctrl, "12", &"camp_blade")
	eq(r12.time_seconds, 16.0, "战败路线 12 耗时 16 秒")
	eq(int(r12.player_hp), 28, "战败路线 12 战后生命 28")
	ctrl.pickup_drops()

	# 15 首次挑战：失败，不磨损敌人
	_go(ctrl, ["15"])
	var r15 := _fight(ctrl, "15", &"bandit_chief", false)
	check(not r15.winner_is_player(), "战败路线头子首次挑战应失败")
	eq(r15.time_seconds, 14.0, "头子首次挑战 14 秒")
	eq(int(r15.player_hp), 0, "头子首次挑战玩家生命归零")
	eq(ctrl.state.defeats, 1, "消耗一次战败次数")
	eq(ctrl.state.current_hp, 120.0, "战败后免费恢复满血")
	check(not ctrl.state.main_completed, "失败不完成主线")

	# 免费回城补强后免费重试
	_go(ctrl, ["12", "11", "08", "06", "05", "03"])
	eq(_sell_n(ctrl, &"scrap_material", 3, "03", &"clinic"), 3, "应能在商店出售已收集的材料")
	var bs := _buy(ctrl, "03", &"gear_shop", &"short_blade")
	check(bs.success, "应能补买短刃：%s" % bs.reason)
	_equip(ctrl, &"short_blade")
	eq(ctrl.state.money, 12, "补强后余额 12")
	_go(ctrl, ["05", "06", "08", "11", "12", "15"])
	var retry := _fight(ctrl, "15", &"bandit_chief")
	check(retry.winner_is_player(), "补强后应击败头子")
	eq(retry.time_seconds, 14.0, "头子重试 14 秒")
	eq(int(retry.player_hp), 96, "头子重试后生命 96")
	ctrl.pickup_drops()
	eq(ctrl.state.money, 42, "头子重试后现金 42（战斗 6 + 主线 24）")

	# 回归：出售剩余材料并治疗
	_go(ctrl, ["12", "11", "08", "06", "05", "03"])
	eq(_sell_n(ctrl, &"scrap_material", 2, "03", &"clinic"), 2, "应出售剩余两份材料")
	ctrl.return_to_deity()
	ctrl.deity_heal()
	eq(ctrl.state.money, 50, "回归资金 50")
	eq(ctrl.state.current_hp, 120.0, "回归治疗回满")

	# 阶段首次挑战：不补强仍失败
	ctrl.confirm_stage_battle()
	ctrl.active_engine.run_all()
	var boss1: BattleResult = ctrl.active_engine.result()
	check(not boss1.winner_is_player(), "未补强的阶段挑战应失败")
	ctrl.settle_stage_battle(ctrl.active_engine)
	eq(ctrl.state.defeats, 2, "阶段首次失败累计 2 次战败")
	eq(ctrl.state.money, 50, "阶段失败不发奖励")
	check(ctrl.state.is_running(), "两次战败后试炼仍继续")

	# 商店不因战败免费重置：库存对象仍是同一个
	var deity1 := ctrl.economy.shops.deity_shop(ctrl.state)
	ctrl.settle_stage_battle(ctrl.active_engine)
	var deity2 := ctrl.economy.shops.deity_shop(ctrl.state)
	check(deity1 == deity2, "阶段战败不重置商店")

	# 购买技能后重试
	var sk := _buy(ctrl, "__deity__", &"deity_mixed", &"ever_stronger")
	check(sk.success, "应能买到越战越勇：%s" % sk.reason)
	eq(ctrl.state.money, 38, "战败路线最终余额 38")
	ctrl.confirm_stage_battle()
	ctrl.active_engine.run_all()
	var boss2: BattleResult = ctrl.active_engine.result()
	check(boss2.winner_is_player(), "补强后应击败同一固定对手")
	eq(boss2.time_seconds, 22.0, "重试耗时 22 秒")
	eq(int(boss2.player_hp), 60, "重试战后生命 60")
	ctrl.settle_stage_battle(ctrl.active_engine)
	eq(ctrl.state.defeats, 2, "最终累计 2 次战败")
	eq(ctrl.state.state, RunState.STATE_STAGE_COMPLETE, "应取得下一阶段资格")


func _test_stage_opponent_fixed() -> void:
	var ctrl := _new_run(41, {}, {})
	ctrl.state.main_completed = true
	var ret := ctrl.return_to_deity()
	check(ret.success, "主线完成后应能回归：%s" % ret.reason)
	check(ctrl.state.returned_to_deity, "应已回归主神空间")
	var blocked := ctrl.travel_to("02")
	check(not blocked.success, "回归后不可再进入武道世界")
	check(blocked.reason.begins_with("已回归"), "回归后旅行应被服务层拒绝")
	var first := ctrl.encounters.ensure_stage_opponent(ctrl.state).duplicate()
	ctrl.deity_heal()
	ctrl.open_stage_preview()
	var second := ctrl.encounters.ensure_stage_opponent(ctrl.state)
	eq(str(first["template_id"]), str(second["template_id"]), "阶段对手生成一次后固定")
	eq((first["equipment"] as Array).size(), (second["equipment"] as Array).size(), "重试不改变对手配置")

	# 第三次战败结束试炼；认输是独立操作
	ctrl.state.defeats = 2
	ctrl.confirm_stage_battle()
	ctrl.active_engine.run_all()
	ctrl.settle_stage_battle(ctrl.active_engine)
	if not ctrl.state.is_running():
		eq(ctrl.state.state, RunState.STATE_FAILED, "第三次战败应结束试炼")
	var ctrl2 := _new_run(42, {}, {})
	ctrl2.surrender()
	eq(ctrl2.state.state, RunState.STATE_SURRENDERED, "认输按失败结算且不等同回归")
