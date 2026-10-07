class_name CombatRegressionTest
extends TestSuite
## M1 验收：无画面结果与既有确定性基准一致（对齐 _验证/战斗数值验证.js 的断言）。
## 基准来源：《游戏可玩原型技术方案.md》第 16 节；_验证/战斗数值验证结果.json。

const ORACLE := "既有验证脚本"

var catalog: ContentCatalog
var rng: RandomService
var engine: CombatEngine


func _init() -> void:
	suite_name = "M1 战斗回归"


func run() -> void:
	catalog = ContentCatalog.load_default()
	rng = RandomService.create(1)
	engine = CombatEngine.new()
	engine.catalog = catalog
	engine.rng = rng

	_test_basic_regressions()
	_test_frame_ordering()
	_test_route_normal()
	_test_route_low()
	_test_route_failure()
	_test_retries()
	_test_controls()
	_test_clearing()


# ---------------------------------------------------------------------------
# 构造与执行
# ---------------------------------------------------------------------------

func _player(items: Array, hp: float = -1.0, traits: bool = true) -> CombatActor:
	var spec := {
		"side": CombatActor.SIDE_PLAYER,
		"display_name": "玩家",
		"max_hp": 120.0 if traits else 100.0,
		"hp": 120.0 if traits else 100.0,
		"items": items,
	}
	if traits:
		spec["profession"] = &"warrior"
		spec["bloodline"] = &"sturdy"
	if hp >= 0.0:
		spec["hp"] = hp
	return CombatEngine.build_actor(catalog, spec)


func _raw_player(items: Array, hp: float = 100.0) -> CombatActor:
	return CombatEngine.build_actor(catalog, {
		"side": CombatActor.SIDE_PLAYER,
		"display_name": "玩家",
		"max_hp": 100.0,
		"hp": hp,
		"items": items,
	})


func _enemy(template_id: StringName) -> CombatActor:
	return CombatEngine.build_enemy(catalog, catalog.enemy(template_id))


## 不会反击的靶子，用于观察冷却、控制与沙尘暴，不影响任何正式数值
func _dummy(hp: float, items: Array = []) -> CombatActor:
	return CombatEngine.build_actor(catalog, {
		"side": CombatActor.SIDE_ENEMY,
		"display_name": "靶子",
		"max_hp": hp,
		"hp": hp,
		"items": items,
	})



func _items(list: Array) -> Array:
	var out := []
	for entry in list:
		var def_id: StringName = entry[0]
		var quality: int = int(entry[1]) if entry.size() > 1 else 0
		out.append({"definition_id": def_id, "quality": quality})
	return out


func _fight(p: CombatActor, e: CombatActor, battle_id: String) -> BattleResult:
	var eng := CombatEngine.new()
	eng.catalog = catalog
	eng.rng = rng
	eng.begin(p, e, battle_id, "battle/%s" % battle_id)
	return eng.run_all()


# ---------------------------------------------------------------------------
# 第 16 节：必须通过的战斗与帧顺序验证
# ---------------------------------------------------------------------------

func _test_basic_regressions() -> void:
	# 无职业血统：青铜长刀＋护身佩对头子，28秒胜、剩28生命
	var r1 := _fight(_raw_player(_items([[&"long_blade"], [&"ward_charm"]])), _enemy(&"bandit_chief"), "reg1")
	eq(r1.time_seconds, 28.0, "长刀＋护身佩对头子耗时")
	eq(r1.player_hp, 28.0, "长刀＋护身佩对头子剩余生命")
	check(r1.winner_is_player(), "长刀＋护身佩对头子应获胜")

	# 加青铜短刃，18秒胜、剩76
	var r2 := _fight(_raw_player(_items([[&"long_blade"], [&"ward_charm"], [&"short_blade"]])), _enemy(&"bandit_chief"), "reg2")
	eq(r2.time_seconds, 18.0, "加短刃对头子耗时")
	eq(r2.player_hp, 76.0, "加短刃对头子剩余生命")
	check(r2.winner_is_player(), "加短刃对头子应获胜")

	# 同配置以72生命挑战头子，第28秒同死，判玩家失败
	var r3 := _fight(_raw_player(_items([[&"long_blade"], [&"ward_charm"]]), 72.0), _enemy(&"bandit_chief"), "reg3")
	eq(r3.time_seconds, 28.0, "72生命挑战头子耗时")
	eq(r3.player_hp, 0.0, "72生命挑战头子剩余生命")
	check(not r3.winner_is_player(), "同死应判玩家失败")
	check(r3.same_step_death, "应标记为同一步死亡")


func _test_frame_ordering() -> void:
	# 护身佩自带被动：当使用武器时充能此物品 1 秒；首释放因此为 4.1 秒而不是 5.0 秒
	var p := _raw_player(_items([[&"long_blade"], [&"ward_charm"]]))
	var e := _enemy(&"bandit_chief")
	var eng := CombatEngine.new()
	eng.catalog = catalog
	eng.rng = rng
	eng.begin(p, e, "order1", "battle/order1")
	var ward := p.items[1]
	var first_ward_use_step := -1
	while not eng.is_finished() and first_ward_use_step < 0:
		eng.step()
		# 护身佩释放后 CD 被重置为完整 CD，据此判断本步是否释放
		if ward.cooldown_remaining_ms == ward.base_cd_ms and ward.uses == 1:
			first_ward_use_step = eng.current_step()
	eq(first_ward_use_step, 41, "护身佩首次释放应为 4.1 秒（武器使用触发充能 1 秒）")

	# 前 30 秒护盾获取量：开启自身充能为 84（青铜 12 × 7 次），关闭为 72（对照只用于计算）
	# 使用不会反击的靶子，保证战斗持续到 30 秒
	var p2 := _raw_player(_items([[&"long_blade"], [&"ward_charm"]]))
	var eng2 := CombatEngine.new()
	eng2.catalog = catalog
	eng2.rng = rng
	eng2.begin(p2, _dummy(100000.0), "order2", "battle/order2")
	while not eng2.is_finished() and eng2.current_step() < 300:
		eng2.step()
	eq(p2.shield_gained, 84.0, "前 30 秒护身佩累计护盾 84（青铜 12 × 7 次）")

	var knight := p.items[0]
	check(knight.base_cd_ms == 4000, "长刀 CD 为 4 秒")
	check(ward.base_cd_ms == 5000, "护身佩 CD 为 5 秒")
	check(ward.self_passive == ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE, "护身佩自带武器触发充能被动")


func _test_route_normal() -> void:
	# 正常路线：五场世界战斗后 102 生命
	var hp := 120.0
	var steps: Array[Dictionary] = [
		{"node": "02", "enemy": &"bandit", "items": [[&"long_blade"]], "t": 16.0, "hp": 80.0, "heal_first": false},
		{"node": "05", "enemy": &"bandit", "items": [[&"long_blade"], [&"ward_charm"]], "t": 16.0, "hp": 72.0, "heal_first": false},
		{"node": "08", "enemy": &"mountain_guard", "items": [[&"long_blade"], [&"ward_charm"], [&"short_blade"]], "t": 16.0, "hp": 102.0, "heal_first": true},
		{"node": "12", "enemy": &"camp_blade", "items": [[&"long_blade"], [&"ward_charm", 1], [&"short_blade"]], "t": 8.0, "hp": 102.0, "heal_first": false},
		{"node": "15", "enemy": &"bandit_chief", "items": [[&"long_blade", 1], [&"ward_charm", 1], [&"short_blade"]], "t": 12.0, "hp": 102.0, "heal_first": false},
	]
	for s in steps:
		if bool(s["heal_first"]):
			hp = minf(120.0, hp + 30.0)
		var r := _fight(_player(_items(s["items"]), hp), _enemy(s["enemy"]), "normal_%s" % s["node"])
		eq(r.time_seconds, s["t"], "正常路线 %s 耗时（%s）" % [s["node"], ORACLE])
		eq(r.player_hp, s["hp"], "正常路线 %s 战后生命（%s）" % [s["node"], ORACLE])
		check(r.winner_is_player(), "正常路线 %s 应获胜" % s["node"])
		hp = r.player_hp
	eq(hp, 102.0, "正常路线主线后生命")


func _test_route_low() -> void:
	# 全材料路线：最后一战 14 秒、剩 78
	var hp := 120.0
	var steps: Array[Dictionary] = [
		{"node": "02", "enemy": &"bandit", "items": [[&"long_blade"]], "t": 16.0, "hp": 80.0, "heal_first": false},
		{"node": "05", "enemy": &"bandit", "items": [[&"long_blade"], [&"ward_charm"]], "t": 16.0, "hp": 72.0, "heal_first": false},
		{"node": "08", "enemy": &"mountain_guard", "items": [[&"long_blade"], [&"ward_charm"], [&"short_blade"]], "t": 16.0, "hp": 102.0, "heal_first": true},
		{"node": "12", "enemy": &"camp_blade", "items": [[&"long_blade"], [&"ward_charm"], [&"short_blade"]], "t": 8.0, "hp": 102.0, "heal_first": false},
		{"node": "15", "enemy": &"bandit_chief", "items": [[&"long_blade"], [&"ward_charm"], [&"short_blade"]], "t": 14.0, "hp": 78.0, "heal_first": false},
	]
	for s in steps:
		if bool(s["heal_first"]):
			hp = minf(120.0, hp + 30.0)
		var r := _fight(_player(_items(s["items"]), hp), _enemy(s["enemy"]), "low_%s" % s["node"])
		eq(r.time_seconds, s["t"], "全材料路线 %s 耗时（%s）" % [s["node"], ORACLE])
		eq(r.player_hp, s["hp"], "全材料路线 %s 战后生命（%s）" % [s["node"], ORACLE])
		hp = r.player_hp
	eq(hp, 78.0, "全材料路线主线后生命")


func _test_route_failure() -> void:
	# 战败路线：山口拖到 33 秒并受沙尘暴 50，头子第 14 秒败
	var hp := 120.0
	var r02 := _fight(_player(_items([[&"long_blade"]]), hp), _enemy(&"bandit"), "fail_02")
	eq(r02.player_hp, 80.0, "战败路线 02 战后生命")
	hp = r02.player_hp

	var r05 := _fight(_player(_items([[&"long_blade"], [&"ward_charm"]]), hp), _enemy(&"bandit"), "fail_05")
	eq(r05.player_hp, 72.0, "战败路线 05 战后生命")
	hp = r05.player_hp

	var r08 := _fight(_player(_items([[&"long_blade"], [&"ward_charm"]]), hp), _enemy(&"mountain_guard"), "fail_08")
	eq(r08.time_seconds, 33.0, "战败路线 08 耗时（跨过沙尘暴起点）")
	eq(r08.player_hp, 10.0, "战败路线 08 战后生命")
	check(r08.enemy_stats["storm_damage"] > 0.0, "战败路线 08 应对敌人造成沙尘暴伤害")
	eq(r08.enemy_stats["storm_damage"], 50.0, "战败路线 08 敌人承受沙尘暴总量")
	hp = minf(120.0, r08.player_hp + 30.0)

	var r12 := _fight(_player(_items([[&"long_blade"], [&"ward_charm"]]), hp), _enemy(&"camp_blade"), "fail_12")
	eq(r12.time_seconds, 16.0, "战败路线 12 耗时")
	eq(r12.player_hp, 28.0, "战败路线 12 战后生命")
	hp = r12.player_hp

	var r15 := _fight(_player(_items([[&"long_blade"], [&"ward_charm"]]), hp), _enemy(&"bandit_chief"), "fail_15")
	eq(r15.time_seconds, 14.0, "战败路线头子首次挑战耗时")
	check(not r15.winner_is_player(), "战败路线头子首次挑战应失败")
	eq(r15.enemy_hp, 42.0, "战败路线头子剩余生命（失败不磨损敌人）")


func _test_retries() -> void:
	# 头子重试 14 秒胜、剩 96；阶段对手补强后 22 秒胜、剩 60
	var head := _fight(_player(_items([[&"long_blade"], [&"ward_charm"], [&"short_blade"]])), _enemy(&"bandit_chief"), "retry_head")
	eq(head.player_hp, 96.0, "头子重试战后生命（%s）" % ORACLE)
	eq(head.time_seconds, 14.0, "头子重试耗时")

	var boss_items := _items([[&"long_blade"], [&"ward_charm"], [&"short_blade"]])
	var p := _player(boss_items)
	p.skills[&"ever_stronger"] = 0
	var stage_set := catalog.stage_set(&"stage_01")
	var dot_template: StageTemplateDef = _template_by_id(stage_set, &"damage_over_time")
	var equipment: Array = dot_template.equipment.duplicate()
	equipment.append(GrantDef.item(&"rejuvenator", 0))
	var e := CombatEngine.build_stage_opponent(catalog, stage_set, equipment, "持续伤害＋治疗")
	var r := _fight(p, e, "retry_boss")
	check(r.winner_is_player(), "阶段对手补强后应获胜")
	eq(r.player_hp, 60.0, "阶段对手补强后战后生命（%s）" % ORACLE)
	eq(r.time_seconds, 22.0, "阶段对手补强后耗时（%s）" % ORACLE)


func _template_by_id(s: StageSetDef, id: StringName) -> StageTemplateDef:
	for t in s.templates:
		if t.template_id == id:
			return t
	return null


# ---------------------------------------------------------------------------
# 控制、连锁与结算边界
# ---------------------------------------------------------------------------

func _test_controls() -> void:
	# 冰冻中可充能但不能释放；冰冻不取消已锁定的释放
	var p := _raw_player(_items([[&"long_blade"], [&"ward_charm"]]))
	var e := _enemy(&"bandit_chief")
	var eng := CombatEngine.new()
	eng.catalog = catalog
	eng.rng = rng
	eng.begin(p, e, "ctrl1", "battle/ctrl1")
	var ward := p.items[1]
	ward.freeze_ms = 3000
	var released_during_freeze := 0
	for i in 100:
		eng.step()
		if eng.current_step() <= 30 and ward.locked_this_step:
			released_during_freeze += 1
		if eng.is_finished():
			break
	eq(released_during_freeze, 0, "冰冻期间不得释放（冰冻 3 秒覆盖前 30 步）")

	# 加速、减速同时存在时按正常速度推进
	var item := BattleItemState.new()
	item.base_cd_ms = 4000
	item.cooldown_remaining_ms = 4000
	item.haste_ms = 5000
	item.slow_ms = 5000
	eq(item.natural_advance_ms(100), 100, "加速与减速同时存在时按正常速度")
	item.slow_ms = 0
	eq(item.natural_advance_ms(100), 200, "只有加速时为 2 倍")
	item.slow_ms = 5000
	item.haste_ms = 0
	eq(item.natural_advance_ms(100), 50, "只有减速时为 1/2")

	# 充能到就绪最早下一步释放，溢出不储存
	var p2 := _raw_player(_items([[&"long_blade"], [&"ward_charm"]]))
	var w2 := p2.items[1]
	var eng2 := CombatEngine.new()
	eng2.catalog = catalog
	eng2.rng = rng
	eng2.begin(p2, _enemy(&"bandit"), "ctrl2", "battle/ctrl2")
	for i in 41:
		eng2.step()
	# 长刀在 4.0 秒释放：护身佩被充能 1 秒后应最早在下一步释放
	check(w2.uses >= 1, "护身佩应被武器使用事件充能后释放")
	check(w2.cooldown_remaining_ms >= 0, "充能不能产生负冷却")

	# 沙尘暴自第 30 秒第一跳 5 开始，不在 30 秒直接判负
	var p3 := _raw_player(_items([[&"long_blade"], [&"tower_shield"]]))
	var e3 := _dummy(100000.0)
	var eng3 := CombatEngine.new()
	eng3.catalog = catalog
	eng3.rng = rng
	eng3.begin(p3, e3, "storm1", "battle/storm1")
	while not eng3.is_finished() and eng3.current_step() < 300:
		eng3.step()
	near(p3.storm_damage, 5.0, 0.001, "沙尘暴首跳伤害（第 30 秒）")
	near(e3.storm_damage, 5.0, 0.001, "沙尘暴对双方同时施加等额伤害")
	check(p3.is_alive(), "第 30 秒不应直接判负")
	# 每秒递增一级：第 31 秒（第 310 步）累计 5 + 10
	for i in 10:
		eng3.step()
	near(p3.storm_damage, 15.0, 0.001, "沙尘暴第 31 秒累计 15（5 + 10）")


func _test_clearing() -> void:
	# 同帧治疗可以救命；满血治疗仍产生治疗事件；中毒绕过护盾
	var p := _raw_player(_items([[&"long_blade"], [&"rejuvenator"]]), 100.0)
	p.max_hp = 100.0
	var e := _enemy(&"bandit")
	var eng := CombatEngine.new()
	eng.catalog = catalog
	eng.rng = rng
	eng.begin(p, e, "heal1", "battle/heal1")
	var r := eng.run_all()
	check(r.player_stats["heal_computed"] >= 0.0, "应记录计算治疗量")
	check(r.player_stats["heal_actual"] >= 0.0, "应记录实际恢复量")
	check(r.player_stats["heal_computed"] >= r.player_stats["heal_actual"], "计算治疗量不小于实际恢复量")

	# 中毒绕过护盾
	var pc := _raw_player(_items([[&"long_blade"]]))
	pc.shield = 100.0
	var ec := CombatEngine.build_enemy(catalog, catalog.enemy(&"bandit"))
	var engc := CombatEngine.new()
	engc.catalog = catalog
	engc.rng = rng
	engc.begin(pc, CombatEngine.build_actor(catalog, {
		"side": CombatActor.SIDE_ENEMY, "display_name": "毒手", "max_hp": 48.0,
		"items": [{"definition_id": &"poison_needle", "quality": 0}],
	}), "poison1", "battle/poison1")
	var rc := engc.run_all()
	check(rc.player_stats["damage_taken_hp"] > 0.0, "中毒伤害应直接扣生命")
	check(rc.player_stats["damage_taken_shield"] == 0.0, "中毒不应被护盾抵挡")
