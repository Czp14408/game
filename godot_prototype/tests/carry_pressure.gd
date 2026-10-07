extends SceneTree
## 背包容量压力样本（GitHub Issue #8 / 验收条目 4 的证据）。
##
## 用法：
##   godot --headless --path . --script res://tests/carry_pressure.gd -- --out <输出目录>
##
## 目的：补上《游戏最小战斗与经济方案.md》§7.1 明确留下的缺口——
## "本样本容量未接近上限，不能据此证明十点背包的舍弃体验已成立"。
##
## 两组样本沿用与 tests/world_flow_test.gd 相同的正常路线骨架与固定验证库存，
## 只替换掉落序列，使「备用装备 / 重复件 / 恢复品 / 材料」同时竞争十点背包。
## 每一步记录战斗栏与背包占用；容量不足时记录真实失败原因，再记录随后的取舍动作。
## 只记录与复用既有规则，不修改任何数值。
##
## 退出码：0 无溢出（本样本目的就是制造溢出，故溢出不算失败）；1 存在脚本错误。

const DEFAULT_OUT_DIR := "D:/clawWorkSpace/game/_验证/复演账本"

const SCENARIOS := [
	{
		"key": "duplicates", "title": "压力样本 A：重复件堆叠",
		"intent": "四场掉落均为 3 格重锤，检验「想全部带走重复件用于合成」时背包何时到顶，"
				+ "以及合成能否腾出空间。",
		"drops": {"02": "bandit_knife", "05": "scrap_material", "08": "heavy_hammer",
				"12": "heavy_hammer", "15": "heavy_hammer"},
		"buys": [&"ward_charm", &"short_blade", &"recovery_draught"],
		"extra": &"heavy_hammer",
	},
	{
		"key": "mixed", "title": "压力样本 B：备用装备＋重复件＋恢复品＋材料",
		"intent": "掉落含材料、与已装备件重复的护身佩与短刃、以及 3 格重锤；"
				+ "另购置恢复品并保留全部材料，检验四类占用同时竞争十点背包。",
		"drops": {"02": "scrap_material", "05": "ward_charm", "08": "short_blade",
				"12": "heavy_hammer", "15": "heavy_hammer"},
		"buys": [&"ward_charm", &"short_blade"],
		"extra": &"long_blade",
	},
]


func _initialize() -> void:
	var out_dir := DEFAULT_OUT_DIR
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]

	var sample := CarryPressure.new()
	sample.out_dir = out_dir
	sample.generate()
	print(sample.summary())
	var err := sample.write()
	if err != OK:
		push_error("写出压力样本失败：%s" % error_string(err))
	print("── 压力样本输出目录：%s" % out_dir)
	quit(1 if sample.failed > 0 else 0)


# ===========================================================================

class CarryPressure extends TestSuite:
	const SEED := 20261007

	var out_dir: String = DEFAULT_OUT_DIR
	var catalog: ContentCatalog
	var scenarios: Array[Dictionary] = []
	var _ctrl: RunController
	var _lines: Array[Dictionary] = []

	func _init() -> void:
		suite_name = "R0 背包容量压力样本"

	func generate() -> void:
		catalog = ContentCatalog.load_default()
		note("引擎 %s，内容版本 %s；战斗栏上限 %d 点，背包上限 %d 点"
				% [Engine.get_version_info()["string"], catalog.content_version,
				RunState.BAR_CAPACITY, RunState.INVENTORY_CAPACITY])
		for sc in SCENARIOS:
			_run_scenario(sc)

	# ------------------------------------------------------------------
	# 工具
	# ------------------------------------------------------------------

	func _new_run(seed_value: int, drops: Dictionary) -> RunController:
		var ctrl := RunController.new()
		ctrl.catalog = catalog
		ctrl.start_new_app(seed_value)
		ctrl.new_trial(&"warrior", &"sturdy", seed_value)
		ctrl.encounters.drop_override = drops
		ctrl.encounters.stage_override = {"template": &"damage_over_time", "extra": &"rejuvenator"}
		return ctrl

	func _fix_shop(ctrl: RunController, node_id: String, shop_id: StringName, ids: Array) -> void:
		var s := ShopState.new()
		s.shop_key = "%s/%s" % [node_id, shop_id]
		s.shop_id = shop_id
		for entry in ids:
			var slot := ShopState.Slot.new()
			slot.item = ctrl.state.new_instance(entry[0], 0)
			slot.item.location = ItemInstance.LOC_NONE
			s.slots.append(slot)
		ctrl.state.node_state(node_id).shops[shop_id] = s

	func _slot_of(shop: ShopState, def_id: StringName) -> int:
		for i in shop.slots.size():
			if shop.slots[i].item != null and shop.slots[i].item.definition_id == def_id:
				return i
		return -1

	func _buy(ctrl: RunController, node_id: String, shop_id: StringName, def_id: StringName) -> OperationResult:
		ctrl.open_shop("%s/%s" % [node_id, shop_id])
		var idx := _slot_of(ctrl.current_shop(), def_id)
		if idx < 0:
			return OperationResult.fail("固定库存里没有 %s" % def_id)
		return ctrl.buy_slot(idx)

	func _equip(ctrl: RunController, def_id: StringName) -> bool:
		for it in ctrl.state.inventory:
			if it.definition_id == def_id:
				return ctrl.equip(it.instance_id).success
		return false

	func _go(ctrl: RunController, path: Array) -> void:
		for node_id in path:
			var r := ctrl.travel_to(node_id)
			check(r.success, "进入 %s 失败：%s" % [node_id, r.reason])

	func _fight(ctrl: RunController, node_id: String, template_id: StringName) -> void:
		var key := ""
		for k in ctrl.node_enemy_keys():
			var es := ctrl.encounters.ensure(ctrl.state, node_id, k)
			if es.enemy_template_id == template_id and not es.defeated:
				key = k
				break
		if key == "":
			check(false, "%s 号节点找不到 %s" % [node_id, template_id])
			return
		ctrl.open_pre_battle(key)
		ctrl.confirm_battle()
		ctrl.active_engine.run_all()
		ctrl.settle_battle(ctrl.active_engine)

	func _held_text(arr: Array) -> String:
		var parts := PackedStringArray()
		for it in arr:
			parts.append("%s%s(%d)" % [PriceTable.QUALITY_NAMES[it.quality],
					catalog.item_display(it.definition_id), it.size(catalog)])
		return "、".join(parts) if not parts.is_empty() else "（空）"

	func _snap(ctrl: RunController, step: String, note_text: String) -> void:
		_lines.append({
			"step": step,
			"bar": "%d/%d" % [ctrl.state.bar_used(), RunState.BAR_CAPACITY],
			"bag": "%d/%d" % [ctrl.state.inventory_used(), RunState.INVENTORY_CAPACITY],
			"bar_items": _held_text(ctrl.state.battle_bar),
			"bag_items": _held_text(ctrl.state.inventory),
			"money": ctrl.state.money,
			"note": note_text,
		})

	func _pickup(ctrl: RunController, step: String) -> void:
		if ctrl.encounter_state() == null:
			_snap(ctrl, step, "本节点无战后掉落")
			return
		var before_bag := ctrl.state.inventory_used()
		var got := 0
		var left := 0
		for x in ctrl.pickup_drops():
			if bool(x["ok"]):
				got += 1
			else:
				left += 1
		var txt := "拾取 %d 件，背包 %d→%d/%d" % [got, before_bag, ctrl.state.inventory_used(),
				RunState.INVENTORY_CAPACITY]
		if left > 0:
			txt += "；**%d 件因背包空间不足未拾取**" % left
		_snap(ctrl, step, txt)

	func _instances_of(ctrl: RunController, def_id: StringName) -> Array:
		var out: Array = []
		for it in ctrl.state.all_instances():
			if it.definition_id == def_id and ctrl.state.is_held(it.instance_id):
				out.append(it)
		return out

	func _sell_materials(ctrl: RunController) -> int:
		var sold := 0
		while true:
			var arr := _instances_of(ctrl, &"scrap_material")
			if arr.is_empty():
				break
			ctrl.open_shop("03/gear_shop")
			if not ctrl.sell(arr[0].instance_id).success:
				break
			sold += 1
		return sold

	# ------------------------------------------------------------------

	func _run_scenario(sc: Dictionary) -> void:
		var ctrl := _new_run(SEED, sc["drops"])
		_ctrl = ctrl
		_lines = []
		_fix_shop(ctrl, "03", &"gear_shop", [[&"ward_charm"], [&"short_blade"], [&"rejuvenator"], [&"fire_oil"]])
		_fix_shop(ctrl, "03", &"clinic", [[&"recovery_draught"], [&"rejuvenator"]])
		_snap(ctrl, "开局", "起始青铜长刀(2)已装备，背包空，现金 30")

		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
		_go(ctrl, ["02"])
		_fight(ctrl, "02", &"bandit")
		_pickup(ctrl, "02 战后")
		ctrl.talk_to(NodeDef.NPC_QUEST_CHALLENGE)

		_go(ctrl, ["03"])
		var sold0 := 0
		while true:
			var arr := _instances_of(ctrl, &"bandit_knife")
			if arr.is_empty():
				break
			ctrl.open_shop("03/gear_shop")
			if not ctrl.sell(arr[0].instance_id).success:
				break
			sold0 += 1
		if sold0 > 0:
			_snap(ctrl, "03 出售", "出售土匪短刀 %d 件，回收 +%d" % [sold0, sold0 * 3])
		for id in (sc["buys"] as Array):
			var r := _buy(ctrl, "03", &"gear_shop", id)
			if not r.success:
				r = _buy(ctrl, "03", &"clinic", id)
			if r.success:
				_equip(ctrl, id)
		_snap(ctrl, "03 采购并装备", "采购：%s（已装备）" % _buy_list(sc["buys"]))

		_go(ctrl, ["05"])
		_fight(ctrl, "05", &"bandit")
		_pickup(ctrl, "05 战后")

		_go(ctrl, ["03"])
		var sold_m := _sell_materials(ctrl)
		if sold_m > 0:
			_snap(ctrl, "03 重访出售", "出售材料 %d 份，回收 +%d" % [sold_m, sold_m * 4])

		_go(ctrl, ["01"])
		ctrl.talk_to(NodeDef.NPC_QUEST_SIDE)
		_go(ctrl, ["03", "05", "06"])
		ctrl.talk_to(NodeDef.NPC_INTEL_TARGET)

		_go(ctrl, ["08"])
		_fight(ctrl, "08", &"mountain_guard")
		_pickup(ctrl, "08 战后")

		_go(ctrl, ["11", "12"])
		_fight(ctrl, "12", &"camp_blade")
		_pickup(ctrl, "12 战后")

		_go(ctrl, ["15"])
		_fight(ctrl, "15", &"bandit_chief")
		_pickup(ctrl, "15 战后（满包临界）")
		check(ctrl.state.main_completed, "主线应已完成")

		# 再取一件：检验容量是否真的到顶
		_overflow_probe(ctrl, sc["extra"])

		# 取舍动作
		_resolve(ctrl)

		scenarios.append({
			"title": sc["title"], "key": sc["key"], "intent": sc["intent"],
			"drops": sc["drops"], "buys": _buy_list(sc["buys"]), "extra": String(sc["extra"]),
			"lines": _lines.duplicate(true),
			"bar_used": ctrl.state.bar_used(), "bag_used": ctrl.state.inventory_used(),
			"money": ctrl.state.money,
		})

	## 容量探针：直接尝试拾取一件，记录真实失败原因
	func _overflow_probe(ctrl: RunController, def_id: StringName) -> void:
		# 与 encounter_service._generate_drops / world.open_container 一致：
		# 未拾取成功的掉落保持 LOC_NONE，不进入持有集合。
		var it := ctrl.state.new_instance(def_id, 0, "15")
		it.location = ItemInstance.LOC_NONE
		var before := ctrl.state.inventory_used()
		var r := ctrl.inventory.pickup(ctrl.state, it)
		if r.success:
			_snap(ctrl, "容量探针", "尝试再拾取 1 件青铜%s：成功，背包 %d→%d/%d（本样本未到上限）"
					% [catalog.item_display(def_id), before, ctrl.state.inventory_used(),
					RunState.INVENTORY_CAPACITY])
		else:
			_snap(ctrl, "容量探针", "尝试再拾取 1 件青铜%s：**失败——%s**（背包 %d/%d）"
					% [catalog.item_display(def_id), r.reason, ctrl.state.inventory_used(),
					RunState.INVENTORY_CAPACITY])

	## 取舍：先合成同名同品质重复件（腾空间且不花钱），再出售材料回收现金
	func _resolve(ctrl: RunController) -> void:
		var acted := false
		for def_id in [&"heavy_hammer", &"ward_charm", &"short_blade", &"long_blade", &"fire_oil"]:
			var dupes := _instances_of(ctrl, def_id)
			while dupes.size() >= 2:
				var a: ItemInstance = dupes[0]
				var b: ItemInstance = dupes[1]
				var r := ctrl.synthesize(a.instance_id, b.instance_id)
				if not r.success:
					break
				acted = true
				_snap(ctrl, "取舍·合成", "两件%s%s → 一件%s%s：持有实例 −1，占用 −%d 点"
						% [PriceTable.QUALITY_NAMES[a.quality], catalog.item_display(def_id),
						PriceTable.QUALITY_NAMES[a.quality + 1], catalog.item_display(def_id),
						a.size(catalog)])
				dupes = _instances_of(ctrl, def_id)
		var sold := _sell_materials(ctrl)
		if sold > 0:
			acted = true
			_snap(ctrl, "取舍·出售", "出售材料 %d 份，现金 →%d" % [sold, ctrl.state.money])
		if not acted:
			_snap(ctrl, "取舍", "本次固定输入未触发合成或出售")
		else:
			var it := ctrl.state.new_instance(&"scrap_material", 0, "15")
			it.location = ItemInstance.LOC_NONE
			var r2 := ctrl.inventory.pickup(ctrl.state, it)
			_snap(ctrl, "取舍后重试", "取舍后重试拾取材料：%s，背包 %d/%d"
					% ["成功" if r2.success else "仍失败——%s" % r2.reason,
					ctrl.state.inventory_used(), RunState.INVENTORY_CAPACITY])

	func _buy_list(buys: Array) -> String:
		if buys.is_empty():
			return "（不采购）"
		var parts := PackedStringArray()
		for b in buys:
			parts.append(catalog.item_display(b))
		return "、".join(parts)

	# ------------------------------------------------------------------

	func write() -> Error:
		var mk := DirAccess.make_dir_recursive_absolute(out_dir)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return mk
		var f := FileAccess.open(out_dir.path_join("背包容量压力样本.md"), FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(_to_markdown())
		f.close()
		var j := FileAccess.open(out_dir.path_join("背包容量压力样本.json"), FileAccess.WRITE)
		if j == null:
			return FileAccess.get_open_error()
		j.store_string(JSON.stringify({
			"generated_at": Time.get_datetime_string_from_system(),
			"engine": Engine.get_version_info()["string"],
			"content_version": catalog.content_version,
			"seed": SEED,
			"bar_capacity": RunState.BAR_CAPACITY, "bag_capacity": RunState.INVENTORY_CAPACITY,
			"scenarios": scenarios,
			"assertions": {"passed": passed, "failed": failed, "failures": Array(failures)},
		}, "  "))
		j.close()
		return OK

	func _to_markdown() -> String:
		var out := PackedStringArray()
		out.append("# 背包容量压力样本（R0 收尾 · Issue #8 验收条目 4）")
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
		out.append("  --script res://tests/carry_pressure.gd -- --out <输出目录>")
		out.append("```")
		out.append("")
		out.append("战斗栏与背包各 %d 点容量，占用按物品 `size` 累加（不是件数）。固定种子 %d。"
				% [RunState.INVENTORY_CAPACITY, SEED])
		out.append("路程骨架与固定验证库存同《游戏最小战斗与经济方案.md》§7.1 的正常路线，只替换掉落序列。")
		out.append("材料(1)／恢复品(1)／短刃(1)；长刀／护身佩／回春装置／火油器(2)；重锤(3)。")
		out.append("")
		for sc in scenarios:
			out.append("## %s" % sc["title"])
			out.append("")
			out.append("- 意图：%s" % sc["intent"])
			out.append("- 固定掉落：%s" % JSON.stringify(sc["drops"]))
			out.append("- 固定采购：%s" % sc["buys"])
			out.append("")
			out.append("| 步骤 | 战斗栏 | 背包 | 战斗栏内容 | 背包内容 | 现金 | 结果与理由 |")
			out.append("| --- | --- | --- | --- | --- | --- | --- |")
			for ln in (sc["lines"] as Array):
				out.append("| %s | %s | %s | %s | %s | %d | %s |" % [
					ln["step"], ln["bar"], ln["bag"], ln["bar_items"], ln["bag_items"],
					int(ln["money"]), ln["note"]])
			out.append("")
			out.append("终局占用：战斗栏 **%d/%d**，背包 **%d/%d**，现金 %d。"
					% [int(sc["bar_used"]), RunState.BAR_CAPACITY, int(sc["bag_used"]),
					RunState.INVENTORY_CAPACITY, int(sc["money"])])
			out.append("")
		out.append("## 脚本自身断言")
		out.append("")
		out.append("通过 %d，失败 %d。" % [passed, failed])
		for f2 in failures:
			out.append("- ✗ %s" % f2)
		out.append("")
		return "\n".join(out)
