extends SceneTree
## 三路线复演账本生成器（GitHub Issue #8 / 验收条目 2 的证据）。
##
## 用法：
##   godot --headless --path . --script res://tests/replay_ledger.gd -- --out <输出目录>
##
## 与 tests/world_flow_test.gd 使用完全相同的固定输入（掉落序列、验证库存、阶段对手）。
## 本脚本只读取并记录，不改动任何规则、数值与既有断言：
## 实测值与《游戏最小战斗与经济方案.md》第 7 节不一致时，记入账本"偏差"栏，
## 由人决定改文档还是改实现，这里不做静默调整，也不把偏差算作通过。
##
## 退出码：0 无偏差且无脚本错误；1 存在偏差或错误。

const DEFAULT_OUT_DIR := "D:/clawWorkSpace/game/_验证/复演账本"

## 三路线回放固定使用的阶段对手（与 DevTools.stage_override 一致：持续伤害＋治疗）
const FIXED_STAGE := {"template": &"damage_over_time", "extra": &"rejuvenator"}

## 《游戏最小战斗与经济方案.md》§7 记录的期望值，用于对照；不参与任何断言判定。
const DOC_EXPECT := {
	"normal": {
		"fights": {"02": "80", "05": "72", "08": "102", "12": "102", "15": "102"},
		"stage_hp": "48", "stage_seconds": "24",
		"money": 27, "defeats": 0,
	},
	"low": {
		"fights": {"02": "80", "05": "72", "08": "102", "12": "102", "15": "78"},
		"stage_hp": "60", "stage_seconds": "22",
		"money": 38, "defeats": 0,
	},
	"failure": {
		"fights": {"02": "80", "05": "72", "08": "10", "12": "28"},
		"stage_hp": "60", "stage_seconds": "22",
		"money": 38, "defeats": 2,
	},
}


func _initialize() -> void:
	var out_dir := DEFAULT_OUT_DIR
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]

	var ledger := ReplayLedger.new()
	ledger.out_dir = out_dir
	ledger.generate()
	print(ledger.summary())
	var err := ledger.write()
	if err != OK:
		push_error("写出账本失败：%s" % error_string(err))
	print("── 账本输出目录：%s" % out_dir)
	quit(1 if (ledger.failed > 0 or ledger.deltas.size() > 0) else 0)


# ===========================================================================
# 账本生成
# ===========================================================================

class ReplayLedger extends TestSuite:
	var out_dir: String = DEFAULT_OUT_DIR
	var catalog: ContentCatalog
	var deltas: PackedStringArray = []          # 实测与文档记录的偏差
	var _routes: Array[Dictionary] = []
	var _cur: Dictionary = {}
	var _lines: Array[Dictionary] = []
	var _ctrl: RunController = null

	func _init() -> void:
		suite_name = "R0 三路线复演账本"

	func generate() -> void:
		catalog = ContentCatalog.load_default()
		note("引擎 %s，内容版本 %s" % [Engine.get_version_info()["string"], catalog.content_version])
		_route_normal()
		_route_low()
		_route_failure()

	# ------------------------------------------------------------------
	# 工具
	# ------------------------------------------------------------------

	func _new_run(seed_value: int, drops: Dictionary, stage: Dictionary) -> RunController:
		var ctrl := RunController.new()
		ctrl.catalog = catalog
		ctrl.start_new_app(seed_value)
		ctrl.new_trial(&"warrior", &"sturdy", seed_value)
		ctrl.encounters.drop_override = drops
		ctrl.encounters.stage_override = stage
		return ctrl

	func _fix_shop(ctrl: RunController, node_id: String, shop_id: StringName, ids: Array,
			skills: Array = []) -> void:
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

	func _route_shops(ctrl: RunController) -> void:
		_fix_shop(ctrl, "03", &"gear_shop", [[&"ward_charm"], [&"short_blade"], [&"rejuvenator"], [&"fire_oil"]])
		_fix_shop(ctrl, "03", &"clinic", [[&"recovery_draught"], [&"rejuvenator"]])
		_fix_shop(ctrl, "03", &"weapon_shop", [])

	func _deity_store(ctrl: RunController) -> void:
		_fix_shop(ctrl, "__deity__", &"deity_mixed", [[&"short_blade"], [&"rejuvenator"], [&"poison_needle"]],
				[[&"ever_stronger", 0]])

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

	func _equip(ctrl: RunController, def_id: StringName, quality: int = -1) -> void:
		var it := _held_instance(ctrl, def_id, quality)
		if it == null:
			check(false, "应持有 %s 以便装备" % def_id)
			return
		var r := ctrl.equip(it.instance_id)
		check(r.success, "装备 %s 失败：%s" % [def_id, r.reason])

	func _sell_all(ctrl: RunController, def_id: StringName, node_id: String = "03",
			shop_id: StringName = &"gear_shop") -> int:
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

	func _sell_n(ctrl: RunController, def_id: StringName, n: int, node_id: String = "03",
			shop_id: StringName = &"gear_shop") -> int:
		var sold := 0
		for i in n:
			var it := _held_instance(ctrl, def_id)
			if it == null:
				break
			ctrl.open_shop("%s/%s" % [node_id, shop_id])
			if ctrl.sell(it.instance_id).success:
				sold += 1
		return sold

	## 移动：逐个节点记录节点费
	func _go(ctrl: RunController, path: Array) -> void:
		for node_id in path:
			var fee := ctrl.world.entry_fee(ctrl.state, node_id)
			var before := ctrl.state.money
			var r := ctrl.travel_to(node_id)
			check(r.success, "进入 %s 失败：%s" % [node_id, r.reason])
			_row("移动", node_id, ctrl.state.current_hp, _bar_text(ctrl), "—",
					"节点费 %d（现金 %d→%d）" % [fee, before, ctrl.state.money])

	func _fight(ctrl: RunController, node_id: String, template_id: StringName,
			expect_win: bool = true) -> BattleResult:
		var key := ""
		for k in ctrl.node_enemy_keys():
			var es := ctrl.encounters.ensure(ctrl.state, node_id, k)
			if es.enemy_template_id == template_id and not es.defeated:
				key = k
				break
		if key == "":
			check(false, "%s 号节点找不到可挑战的 %s" % [node_id, template_id])
			return null
		var pre_hp := ctrl.state.current_hp
		var config := _bar_text(ctrl)
		ctrl.open_pre_battle(key)
		ctrl.confirm_battle()
		ctrl.active_engine.run_all()
		var result: BattleResult = ctrl.active_engine.result()
		ctrl.settle_battle(ctrl.active_engine)
		_row("战斗", node_id, pre_hp, config, "%.0f" % result.time_seconds,
				"对手 %s，%s" % [template_id, "胜" if result.winner_is_player() else "负"])
		if expect_win and not result.winner_is_player():
			check(false, "%s 号节点 %s 应获胜" % [node_id, template_id])
		return result

	func _bar_text(ctrl: RunController) -> String:
		var parts := PackedStringArray()
		for it in ctrl.state.battle_bar:
			parts.append("%s%s" % [PriceTable.QUALITY_NAMES[it.quality],
					catalog.item_display(it.definition_id)])
		if parts.is_empty():
			return "（空）"
		return "＋".join(parts)

	func _row(kind: String, node: String, pre_hp: float, config: String, seconds: String,
			note_text: String) -> void:
		var st := _ctrl.state
		_lines.append({
			"kind": kind, "node": node, "pre_hp": pre_hp, "config": config,
			"seconds": seconds, "hp": st.current_hp, "money": st.money,
			"defeats": st.defeats, "note": note_text,
		})

	func _begin_route(key: String, title: String, seed_value: int, ctrl: RunController,
			inputs: String) -> void:
		_ctrl = ctrl
		_lines = []
		_cur = {
			"key": key, "title": title, "seed": seed_value, "inputs": inputs,
			"start_money": 30, "start_hp": ctrl.state.current_hp, "start_max_hp": ctrl.state.max_hp,
			"lines": _lines, "stage": {},
		}

	func _end_route(ctrl: RunController) -> void:
		_cur["money"] = ctrl.state.money
		_cur["hp"] = ctrl.state.current_hp
		_cur["max_hp"] = ctrl.state.max_hp
		_cur["defeats"] = ctrl.state.defeats
		_cur["run_state"] = String(ctrl.state.state)
		_cur["lines"] = _lines.duplicate(true)
		_routes.append(_cur)

	## 记录阶段战斗（现有 world_flow_test 的正常路线未实际执行这一步）
	func _stage_battle(ctrl: RunController, label: String) -> BattleResult:
		var pre_hp := ctrl.state.current_hp
		var config := _bar_text(ctrl)
		ctrl.confirm_stage_battle()
		ctrl.active_engine.run_all()
		var result: BattleResult = ctrl.active_engine.result()
		ctrl.settle_stage_battle(ctrl.active_engine)
		_row("阶段战", label, pre_hp, config, "%.0f" % result.time_seconds,
				"固定对手持续伤害＋治疗，%s" % ("胜" if result.winner_is_player() else "负"))
		var st := _ctrl.state
		_cur["stage"] = {
			"hp": st.current_hp, "seconds": "%.0f" % result.time_seconds,
			"money": st.money, "defeats": st.defeats,
			"win": result.winner_is_player(),
		}
		return result

	func _expect(route_key: String, fight_node: String, actual: String) -> String:
		var exp: Dictionary = DOC_EXPECT[route_key]["fights"]
		if not exp.has(fight_node):
			return "—"
		var doc := str(exp[fight_node])
		if doc != actual:
			deltas.append("%s 路线 %s 节点战后生命：文档 %s，实测 %s" % [route_key, fight_node, doc, actual])
			return "%s ⚠" % doc
		return doc

	# ------------------------------------------------------------------
	# 7.1 正常成长
	# ------------------------------------------------------------------

	func _route_normal() -> void:
		var drops := {"02": "bandit_knife", "05": "material", "08": "ward_charm",
				"12": "long_blade", "15": "heavy_hammer"}
		var ctrl := _new_run(20261007, drops, FIXED_STAGE)
		_begin_route("normal", "7.1 正常成长", 20261007, ctrl,
				"02 土匪短刀；05 材料；08 护身佩；12 长刀；15 重锤；阶段对手固定为持续伤害＋治疗")
		_route_shops(ctrl)
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

		_go(ctrl, ["02"])
		var r02 := _fight(ctrl, "02", &"bandit")
		ctrl.pickup_drops()
		ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)
		_row("支线", "02", ctrl.state.current_hp, _bar_text(ctrl), "—", "完成挑战支线，现金 %d" % ctrl.state.money)

		_go(ctrl, ["03"])
		_sell_all(ctrl, &"bandit_knife")
		_row("出售", "03", ctrl.state.current_hp, _bar_text(ctrl), "—",
				"出售土匪短刀，现金 %d" % ctrl.state.money)
		_buy(ctrl, "03", &"gear_shop", &"ward_charm")
		_equip(ctrl, &"ward_charm")

		_go(ctrl, ["05"])
		var r05 := _fight(ctrl, "05", &"bandit")
		ctrl.pickup_drops()

		_go(ctrl, ["03"])
		_sell_all(ctrl, &"scrap_material")
		_buy(ctrl, "03", &"gear_shop", &"short_blade")
		_equip(ctrl, &"short_blade")
		_buy(ctrl, "03", &"clinic", &"recovery_draught")
		var draught := _held_instance(ctrl, &"recovery_draught")
		var used := ctrl.use_recovery(draught.instance_id)
		check(used.success, "应能使用恢复品：%s" % used.reason)
		_row("使用", "03", r05.player_hp, _bar_text(ctrl), "—", "使用恢复品，生命 %d" % int(ctrl.state.current_hp))

		_go(ctrl, ["01"])
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

		_go(ctrl, ["03", "05", "06"])
		ctrl.talk_to(NodeDef.NPC_INTEL_TARGET)
		check(ctrl.state.known_intel.has("chief_node"), "应获得头子准确节点情报")

		_go(ctrl, ["08"])
		var r08 := _fight(ctrl, "08", &"mountain_guard")
		ctrl.pickup_drops()
		var ward_equipped := ctrl.state.battle_bar[1]
		var ward_bronze := _held_other(ctrl, &"ward_charm", 0, ward_equipped.instance_id)
		check(ward_bronze != null, "应持有两件青铜护身佩待合成")
		var syn := ctrl.synthesize(ward_equipped.instance_id, ward_bronze.instance_id)
		check(syn.success, "护身佩应能合成：%s" % syn.reason)
		_row("合成", "08", ctrl.state.current_hp, _bar_text(ctrl), "—", "护身佩升白银")

		_go(ctrl, ["11", "12"])
		var r12 := _fight(ctrl, "12", &"camp_blade")
		ctrl.pickup_drops()
		var blade_equipped := _equipped_instance(ctrl, &"long_blade")
		var blade_drop := _held_other(ctrl, &"long_blade", 0, blade_equipped.instance_id)
		check(blade_drop != null and blade_equipped != null, "应持有两件青铜长刀待合成")
		var syn2 := ctrl.synthesize(blade_equipped.instance_id, blade_drop.instance_id)
		check(syn2.success, "长刀应能合成：%s" % syn2.reason)
		_row("合成", "12", ctrl.state.current_hp, _bar_text(ctrl), "—", "长刀升白银")

		_go(ctrl, ["15"])
		var r15 := _fight(ctrl, "15", &"bandit_chief")
		ctrl.pickup_drops()
		check(ctrl.state.main_completed, "击杀头子应完成主线")
		_row("主线", "15", r15.player_hp, _bar_text(ctrl), "—",
				"主线完成，现金 %d，获重锤入包" % ctrl.state.money)

		_go(ctrl, ["12", "11", "08", "06", "05", "03", "17"])
		_row("探索", "17", ctrl.state.current_hp, _bar_text(ctrl), "—",
				"主线后第 9 个新节点，累计付费节点 %d" % ctrl.state.paid_node_count)

		ctrl.return_to_deity()
		check(ctrl.state.returned_to_deity, "应已回归主神空间")
		var hp_before := ctrl.state.current_hp
		ctrl.deity_heal()
		_row("治疗", "主神空间", hp_before, _bar_text(ctrl), "—",
				"免费治疗 %d→%d" % [int(hp_before), int(ctrl.state.current_hp)])
		check(ctrl.encounters.ensure_stage_opponent(ctrl.state).size() > 0, "应生成阶段对手")

		_stage_battle(ctrl, "持续伤害＋治疗")
		_end_route(ctrl)

	# ------------------------------------------------------------------
	# 7.2 掉落不佳：全材料压力样本
	# ------------------------------------------------------------------

	func _route_low() -> void:
		var all_mat := {"02": "material", "05": "material", "08": "material",
				"12": "material", "15": "material"}
		var ctrl := _new_run(20261008, all_mat, FIXED_STAGE)
		_begin_route("low", "7.2 掉落不佳：全材料压力样本", 20261008, ctrl,
				"五场掉落均为材料；沿用相同验证库存；不进入 17，直接回归")
		_route_shops(ctrl)
		_deity_store(ctrl)
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

		_go(ctrl, ["02"])
		var r02 := _fight(ctrl, "02", &"bandit")
		ctrl.pickup_drops()
		ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)
		_row("支线", "02", ctrl.state.current_hp, _bar_text(ctrl), "—", "完成挑战支线，现金 %d" % ctrl.state.money)

		_go(ctrl, ["03"])
		_buy(ctrl, "03", &"gear_shop", &"ward_charm")
		_equip(ctrl, &"ward_charm")

		_go(ctrl, ["05"])
		var r05 := _fight(ctrl, "05", &"bandit")
		ctrl.pickup_drops()

		_go(ctrl, ["03"])
		_buy(ctrl, "03", &"gear_shop", &"short_blade")
		_equip(ctrl, &"short_blade")
		_buy(ctrl, "03", &"clinic", &"recovery_draught")
		var dr := _held_instance(ctrl, &"recovery_draught")
		ctrl.use_recovery(dr.instance_id)
		_row("使用", "03", r05.player_hp, _bar_text(ctrl), "—", "使用恢复品，生命 %d" % int(ctrl.state.current_hp))

		_go(ctrl, ["01"])
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

		_go(ctrl, ["03", "05", "06", "08"])
		var r08 := _fight(ctrl, "08", &"mountain_guard")
		ctrl.pickup_drops()

		_go(ctrl, ["11", "12"])
		var r12 := _fight(ctrl, "12", &"camp_blade")
		ctrl.pickup_drops()

		_go(ctrl, ["15"])
		var r15 := _fight(ctrl, "15", &"bandit_chief")
		ctrl.pickup_drops()
		check(ctrl.state.main_completed, "应完成主线")
		_row("主线", "15", r15.player_hp, _bar_text(ctrl), "—", "主线完成，现金 %d" % ctrl.state.money)

		_go(ctrl, ["12", "11", "08", "06", "05", "03"])
		var sold := _sell_all(ctrl, &"scrap_material", "03", &"clinic")
		eq(sold, 5, "应出售五份材料")
		_row("出售", "03", ctrl.state.current_hp, _bar_text(ctrl), "—", "出售 %d 份材料" % sold)

		ctrl.return_to_deity()
		var hp_before := ctrl.state.current_hp
		ctrl.deity_heal()
		_row("治疗", "主神空间", hp_before, _bar_text(ctrl), "—",
				"免费治疗 %d→%d" % [int(hp_before), int(ctrl.state.current_hp)])

		var sk := _buy(ctrl, "__deity__", &"deity_mixed", &"ever_stronger")
		check(sk.success, "应能买到越战越勇")
		_row("补强", "主神空间", ctrl.state.current_hp, _bar_text(ctrl), "—",
				"购买青铜越战越勇，现金 %d" % ctrl.state.money)

		_stage_battle(ctrl, "持续伤害＋治疗")
		_end_route(ctrl)

	# ------------------------------------------------------------------
	# 7.3 战败：缺补强到两次失败
	# ------------------------------------------------------------------

	func _route_failure() -> void:
		var all_mat := {"02": "material", "05": "material", "08": "material",
				"12": "material", "15": "material"}
		var ctrl := _new_run(20261009, all_mat, FIXED_STAGE)
		_begin_route("failure", "7.3 战败：缺补强到两次失败", 20261009, ctrl,
				"五场掉落均为材料，05 后不买短刃；15 首次挑战失败后免费回城补强重试")
		_route_shops(ctrl)
		_deity_store(ctrl)
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)

		_go(ctrl, ["02"])
		_fight(ctrl, "02", &"bandit")
		ctrl.pickup_drops()
		ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)
		_row("支线", "02", ctrl.state.current_hp, _bar_text(ctrl), "—", "完成挑战支线，现金 %d" % ctrl.state.money)

		_go(ctrl, ["03"])
		_buy(ctrl, "03", &"gear_shop", &"ward_charm")
		_equip(ctrl, &"ward_charm")

		_go(ctrl, ["05"])
		_fight(ctrl, "05", &"bandit")
		ctrl.pickup_drops()

		_go(ctrl, ["03"])
		_buy(ctrl, "03", &"clinic", &"recovery_draught")
		_go(ctrl, ["01"])
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
		_go(ctrl, ["03", "05", "06", "08"])

		var r08 := _fight(ctrl, "08", &"mountain_guard")
		ctrl.pickup_drops()
		var d8 := _held_instance(ctrl, &"recovery_draught")
		check(d8 != null, "应还持有恢复品")
		ctrl.use_recovery(d8.instance_id)
		_row("使用", "08", r08.player_hp, _bar_text(ctrl), "—", "使用恢复品，生命 %d" % int(ctrl.state.current_hp))

		_go(ctrl, ["11", "12"])
		var r12 := _fight(ctrl, "12", &"camp_blade")
		ctrl.pickup_drops()

		_go(ctrl, ["15"])
		var r15 := _fight(ctrl, "15", &"bandit_chief", false)
		check(not r15.winner_is_player(), "头子首次挑战应失败")
		_eq_int(ctrl.state.defeats, 1, "消耗一次战败次数")
		_row("失败", "15", r12.player_hp, _bar_text(ctrl), "—",
				"头子首次挑战失败，战败后免费恢复至 %d" % int(ctrl.state.current_hp))

		_go(ctrl, ["12", "11", "08", "06", "05", "03"])
		var s3 := _sell_n(ctrl, &"scrap_material", 3, "03", &"clinic")
		eq(s3, 3, "应出售三份材料")
		_buy(ctrl, "03", &"gear_shop", &"short_blade")
		_equip(ctrl, &"short_blade")
		_row("补强", "03", ctrl.state.current_hp, _bar_text(ctrl), "—", "免费回城补买短刃，现金 %d" % ctrl.state.money)

		_go(ctrl, ["05", "06", "08", "11", "12", "15"])
		var retry := _fight(ctrl, "15", &"bandit_chief")
		ctrl.pickup_drops()
		check(retry.winner_is_player(), "补强后应击败头子")
		_row("主线", "15", retry.player_hp, _bar_text(ctrl), "—", "头子重试胜，现金 %d" % ctrl.state.money)

		_go(ctrl, ["12", "11", "08", "06", "05", "03"])
		var s2 := _sell_n(ctrl, &"scrap_material", 2, "03", &"clinic")
		eq(s2, 2, "应出售剩余两份材料")
		ctrl.return_to_deity()
		var hp_before := ctrl.state.current_hp
		ctrl.deity_heal()
		_row("治疗", "主神空间", hp_before, _bar_text(ctrl), "—",
				"免费治疗 %d→%d" % [int(hp_before), int(ctrl.state.current_hp)])

		# 阶段首次挑战：不补强仍失败
		var b1 := _stage_raw(ctrl)
		check(not b1.winner_is_player(), "未补强的阶段挑战应失败")
		_eq_int(ctrl.state.defeats, 2, "阶段首次失败累计 2 次战败")
		_row("阶段战", "主神空间", 120.0, _bar_text(ctrl), "%.0f" % b1.time_seconds,
				"未补强，负；累计战败 %d" % ctrl.state.defeats)

		var sk := _buy(ctrl, "__deity__", &"deity_mixed", &"ever_stronger")
		check(sk.success, "应能买到越战越勇")
		_row("补强", "主神空间", ctrl.state.current_hp, _bar_text(ctrl), "—",
				"购买青铜越战越勇，现金 %d" % ctrl.state.money)

		_stage_battle(ctrl, "持续伤害＋治疗")
		_end_route(ctrl)

	## 只打不记录阶段战斗（用于"未补强的第一次失败"，随后由 _stage_battle 记录成功那次）
	func _stage_raw(ctrl: RunController) -> BattleResult:
		ctrl.confirm_stage_battle()
		ctrl.active_engine.run_all()
		var result: BattleResult = ctrl.active_engine.result()
		ctrl.settle_stage_battle(ctrl.active_engine)
		return result

	func _eq_int(actual: int, expected: int, message: String) -> void:
		eq(actual, expected, message)

	# ------------------------------------------------------------------
	# 输出
	# ------------------------------------------------------------------

	func write() -> Error:
		var dir := out_dir
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return mk
		var md := _to_markdown()
		var f1 := FileAccess.open(dir.path_join("三路线复演账本.md"), FileAccess.WRITE)
		if f1 == null:
			return FileAccess.get_open_error()
		f1.store_string(md)
		f1.close()
		var f2 := FileAccess.open(dir.path_join("三路线复演账本.json"), FileAccess.WRITE)
		if f2 == null:
			return FileAccess.get_open_error()
		f2.store_string(JSON.stringify({
			"generated_at": Time.get_datetime_string_from_system(),
			"engine": Engine.get_version_info()["string"],
			"content_version": catalog.content_version,
			"routes": _routes,
			"deltas": Array(deltas),
			"assertions": {"passed": passed, "failed": failed, "failures": Array(failures)},
		}, "  "))
		f2.close()
		return OK

	func _to_markdown() -> String:
		var out := PackedStringArray()
		out.append("# 三路线复演账本（R0 收尾 · Issue #8 验收条目 2）")
		out.append("")
		out.append("生成时间：%s｜引擎：%s｜内容版本：%s"
				% [Time.get_datetime_string_from_system(), Engine.get_version_info()["string"],
				catalog.content_version])
		out.append("")
		out.append("生成方式（可复现）：")
		out.append("")
		out.append("```bash")
		out.append("cd godot_prototype")
		out.append("/d/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . \\")
		out.append("  --script res://tests/replay_ledger.gd -- --out <输出目录>")
		out.append("```")
		out.append("")
		out.append("固定输入与 `tests/world_flow_test.gd` 完全一致（掉落序列、03 号节点验证库存、"
				+ "阶段对手固定为「持续伤害＋治疗」）。本账本只记录，不修改任何规则或数值。")
		out.append("")
		out.append("预设：职业 武者，血统 强健，基础最大生命 120，起始现金 30。")
		out.append("")
		for route in _routes:
			out.append_array(_route_markdown(route))
			out.append("")
		out.append("## 与《游戏最小战斗与经济方案.md》第 7 节的偏差")
		out.append("")
		if deltas.is_empty():
			out.append("无偏差：上表实测值与文档记录一致。")
		else:
			for d in deltas:
				out.append("- %s" % d)
		out.append("")
		out.append("## 脚本自身断言")
		out.append("")
		out.append("通过 %d，失败 %d。" % [passed, failed])
		for f in failures:
			out.append("- ✗ %s" % f)
		out.append("")
		return "\n".join(out)

	func _route_markdown(route: Dictionary) -> PackedStringArray:
		var out := PackedStringArray()
		out.append("## %s" % route["title"])
		out.append("")
		out.append("- 随机种子：%d" % int(route["seed"]))
		out.append("- 固定输入：%s" % route["inputs"])
		out.append("- 起始：现金 %d，生命 %d/%d" % [int(route["start_money"]), int(route["start_hp"]),
				int(route["start_max_hp"])])
		out.append("")
		out.append("| 步骤 | 节点 | 开战生命 | 战斗栏配置 | 耗时(秒) | 战后生命 | 现金 | 累计战败 | 备注 |")
		out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
		for ln in (route["lines"] as Array):
			out.append("| %s | %s | %d | %s | %s | %d | %d | %d | %s |" % [
				ln["kind"], ln["node"], int(ln["pre_hp"]), ln["config"], ln["seconds"],
				int(ln["hp"]), int(ln["money"]), int(ln["defeats"]), ln["note"]])
		out.append("")
		var st: Dictionary = route.get("stage", {})
		out.append("终局：现金 **%d**，生命 **%d/%d**，累计战败 **%d**，状态 `%s`。"
				% [int(route["money"]), int(route["hp"]), int(route["max_hp"]),
				int(route["defeats"]), route.get("run_state", "")])
		if not st.is_empty():
			out.append("")
			out.append("阶段战：%s，耗时 %s 秒，战后生命 %d，累计战败 %d。"
					% ["胜" if st["win"] else "负", st["seconds"], int(st["hp"]), int(st["defeats"])])
		out.append("")
		return out
