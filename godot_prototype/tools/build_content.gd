extends SceneTree
## 非物品内容生成器：技能、职业、敌人、商店、世界、阶段；物品来自 Excel。
## 用法：godot --headless --path . --script res://tools/build_content.gd
##
## 内容来源：
##   游戏最小战斗与经济方案.md 第 3/4/5/6 节（物品、职业血统、技能、敌人、阶段对手、经济）
##   游戏可玩原型技术方案.md 第 12 节（商店候选池原型默认）、第 9/10 节（世界与节点）
##   游戏单局推演.md 第 3 节（18 节点连接）
## 未获确认的比例均为“可调整原型内容参数”，在内容清单中标记为 prototype_default。

const CONTENT_VERSION := "0.1.0"

const DIRS := [
	"res://data/skills",
	"res://data/traits",
	"res://data/enemies",
	"res://data/shops",
	"res://data/worlds",
	"res://data/stages",
]

var _written: int = 0

func _initialize() -> void:
	for d in DIRS:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	_build_skills()
	_build_traits()
	_build_enemies()
	_build_shops()
	_build_stage_set()
	_build_world()
	_save_manifest()
	print("内容生成完成：%d 个资源，content_version=%s" % [_written, CONTENT_VERSION])
	quit(0)


func _save(res: Resource, rel_path: String) -> void:
	var err := ResourceSaver.save(res, rel_path)
	assert(err == OK, "保存失败：%s（错误码 %d）" % [rel_path, err])
	_written += 1


# 物品与获取渠道仅由 content/items.xlsx 导入；此工具保留非物品内容生成。


func _build_skills() -> void:
	var defs: Array[SkillDef] = []

	var rage := SkillDef.new()
	rage.definition_id = &"ever_stronger"
	rage.display_name = "越战越勇"
	rage.trigger_event = SkillDef.TRIGGER_USE_SHIELD
	rage.effect_type = &"weapon_damage_growth"
	rage.tier_values = PackedFloat64Array([1, 2, 3, 4])
	rage.description = "使用护盾物品后，所有武器本场伤害增加（战后清除）"
	defs.append(rage)

	var flame := SkillDef.new()
	flame.definition_id = &"flame_aegis"
	flame.display_name = "火势护体"
	flame.trigger_event = SkillDef.TRIGGER_APPLY_BURN
	flame.effect_type = &"shield_gain"
	flame.tier_values = PackedFloat64Array([2, 4, 7, 11])
	flame.description = "施加灼烧后获得护盾"
	defs.append(flame)

	var recovery := SkillDef.new()
	recovery.definition_id = &"rejuvenating_aegis"
	recovery.display_name = "回春护体"
	recovery.trigger_event = SkillDef.TRIGGER_HEAL
	recovery.effect_type = &"shield_gain"
	recovery.tier_values = PackedFloat64Array([2, 3, 5, 8])
	recovery.description = "治疗事件后获得护盾，满血也触发"
	defs.append(recovery)

	for d in defs:
		_save(d, "res://data/skills/%s.tres" % d.definition_id)


func _build_traits() -> void:
	var defs: Array[TraitDef] = []

	var warrior := TraitDef.new()
	warrior.trait_id = &"warrior"
	warrior.display_name = "武者"
	warrior.kind = TraitDef.KIND_PROFESSION
	warrior.effect_type = TraitDef.EFFECT_WEAPON_DAMAGE_FLAT
	warrior.effect_amount = 2.0
	warrior.description = "武器攻击伤害增加 2"
	defs.append(warrior)

	var medic := TraitDef.new()
	medic.trait_id = &"medic"
	medic.display_name = "医者"
	medic.kind = TraitDef.KIND_PROFESSION
	medic.effect_type = TraitDef.EFFECT_HEAL_COMPUTED_FLAT
	medic.effect_amount = 2.0
	medic.description = "每次计算治疗量增加 2"
	defs.append(medic)

	var sturdy := TraitDef.new()
	sturdy.trait_id = &"sturdy"
	sturdy.display_name = "强健"
	sturdy.kind = TraitDef.KIND_BLOODLINE
	sturdy.effect_type = TraitDef.EFFECT_MAX_HP_FLAT
	sturdy.effect_amount = 20.0
	sturdy.description = "最大生命增加 20，起始生命 120/120"
	defs.append(sturdy)

	var vampire := TraitDef.new()
	vampire.trait_id = &"vampire"
	vampire.display_name = "吸血"
	vampire.kind = TraitDef.KIND_BLOODLINE
	vampire.effect_type = TraitDef.EFFECT_HEAL_ON_WEAPON_USE
	vampire.effect_amount = 1.0
	vampire.description = "每次使用武器后治疗自身 1 生命（连锁阶段，不能复活）"
	defs.append(vampire)

	for d in defs:
		_save(d, "res://data/traits/%s.tres" % d.trait_id)


func _build_enemies() -> void:
	var defs: Array[EnemyDef] = []

	var bandit := EnemyDef.new()
	bandit.template_id = &"bandit"
	bandit.display_name = "普通土匪"
	bandit.max_hp = 48.0
	bandit.equipment = [GrantDef.item(&"bandit_knife", 0)]
	defs.append(bandit)

	var guard := EnemyDef.new()
	guard.template_id = &"mountain_guard"
	guard.display_name = "山口守路者"
	guard.max_hp = 60.0
	guard.equipment = [GrantDef.item(&"long_blade", 0), GrantDef.item(&"ward_charm", 0)]
	defs.append(guard)

	var camp_blade := EnemyDef.new()
	camp_blade.template_id = &"camp_blade"
	camp_blade.display_name = "营地刀手"
	camp_blade.max_hp = 48.0
	camp_blade.equipment = [GrantDef.item(&"long_blade", 0)]
	defs.append(camp_blade)

	var chief := EnemyDef.new()
	chief.template_id = &"bandit_chief"
	chief.display_name = "土匪头子"
	chief.max_hp = 84.0
	# 敌人额外伤害强化 +6，实际伤害 36；掉落仍为青铜基础伤害 30
	chief.equipment = [GrantDef.item(&"heavy_hammer", 0, 6.0)]
	chief.is_main_target = true
	defs.append(chief)

	for d in defs:
		_save(d, "res://data/enemies/%s.tres" % d.template_id)


func _build_shops() -> void:
	# 物品候选由 Excel 获取渠道维护；此处仅配置商店规则和技能候选。
	var defs: Array[ShopDef] = []

	var weapon := ShopDef.new()
	weapon.shop_id = &"weapon_shop"
	weapon.display_name = "兵器铺"
	defs.append(weapon)

	var gear := ShopDef.new()
	gear.shop_id = &"gear_shop"
	gear.display_name = "装备铺"
	defs.append(gear)

	var clinic := ShopDef.new()
	clinic.shop_id = &"clinic"
	clinic.display_name = "医馆"
	clinic.sells_consumable = true
	defs.append(clinic)

	var skill_shop := ShopDef.new()
	skill_shop.shop_id = &"skill_shop"
	skill_shop.display_name = "技能商人"
	skill_shop.skill_candidates = [&"ever_stronger", &"flame_aegis", &"rejuvenating_aegis"]
	defs.append(skill_shop)

	var deity := ShopDef.new()
	deity.shop_id = &"deity_mixed"
	deity.display_name = "主神混合店"
	deity.mode = ShopDef.MODE_MIXED
	deity.equipment_weight = 0.8
	deity.skill_weight = 0.2
	deity.skill_candidates = [&"ever_stronger", &"flame_aegis", &"rejuvenating_aegis"]
	defs.append(deity)

	for d in defs:
		_save(d, "res://data/shops/%s.tres" % d.shop_id)


func _build_stage_set() -> void:
	var set_ := StageSetDef.new()
	set_.stage_id = &"stage_01"
	set_.display_name = "第一阶段试炼者"
	set_.max_hp = 100.0

	var direct := StageTemplateDef.new()
	direct.template_id = &"direct_attack"
	direct.display_name = "直接攻击"
	direct.equipment = [
		GrantDef.item(&"long_blade", 1),
		GrantDef.item(&"short_blade", 0),
		GrantDef.item(&"ward_charm", 0),
	]
	set_.templates.append(direct)

	var defense := StageTemplateDef.new()
	defense.template_id = &"defense_heal"
	defense.display_name = "防御恢复"
	defense.equipment = [
		GrantDef.item(&"long_blade", 0),
		GrantDef.item(&"tower_shield", 0),
		GrantDef.item(&"rejuvenator", 0),
	]
	set_.templates.append(defense)

	var dot := StageTemplateDef.new()
	dot.template_id = &"damage_over_time"
	dot.display_name = "持续伤害"
	dot.equipment = [
		GrantDef.item(&"fire_oil", 0),
		GrantDef.item(&"poison_needle", 0),
		GrantDef.item(&"ward_charm", 0),
	]
	set_.templates.append(dot)

	# 追加组件池：青铜回春装置 / 缚足器 / 寒封器
	set_.extra_pool = [
		GrantDef.item(&"rejuvenator", 0),
		GrantDef.item(&"leg_binder", 0),
		GrantDef.item(&"frost_seal", 0),
	]

	_save(set_, "res://data/stages/stage_01.tres")


func _node(
	id: String,
	name_: String,
	layout: StringName,
	shops: Array[StringName],
	enemies: Array[StringName],
	npcs: Array[StringName],
	quests: Array[StringName],
	container: StringName,
	main_target: bool = false
) -> NodeDef:
	var n := NodeDef.new()
	n.node_id = id
	n.display_name = name_
	n.layout = layout
	n.shop_ids = shops
	n.enemies = enemies
	n.npc_services = npcs
	n.quest_ids = quests
	n.has_container = container != &""
	n.container_table = container
	n.is_main_target = main_target
	return n


func _conn(a: String, b: String, guard: StringName = &"") -> ConnectionDef:
	var c := ConnectionDef.new()
	c.node_a = a
	c.node_b = b
	c.guard_enemy_id = guard
	return c


func _build_world() -> void:
	var world := WorldDef.new()
	world.world_id = &"wudao_01"
	world.display_name = "武道任务世界"
	world.entry_node_id = "01"

	var town := NodeDef.LAYOUT_TOWN
	var road := NodeDef.LAYOUT_ROAD
	var camp := NodeDef.LAYOUT_CAMP
	var no_shops: Array[StringName] = []
	var no_enemies: Array[StringName] = []
	var no_npcs: Array[StringName] = []
	var no_quests: Array[StringName] = []

	# 城镇：集中服务，每个城镇节点至少一家独立库存的随机店
	world.nodes.append(_node("01", "城镇街市", town, [&"gear_shop"], [&"bandit"],
		[NodeDef.NPC_INTEL_AREA, NodeDef.NPC_QUEST_SIDE], [&"side_road_bandit"], &""))
	world.nodes.append(_node("02", "武馆街区", town, [&"skill_shop"], [&"bandit"],
		[NodeDef.NPC_QUEST_CHALLENGE], [&"side_challenge"], &""))
	world.nodes.append(_node("03", "药铺与兵器铺街区", town, [&"gear_shop", &"weapon_shop", &"clinic"], no_enemies, [NodeDef.NPC_SHOP], no_quests, &""))
	world.nodes.append(_node("04", "城镇后街", town, [&"gear_shop"], no_enemies, [NodeDef.NPC_SHOP], no_quests, &""))
	world.nodes.append(_node("06", "林间驿站", town, [&"clinic"], no_enemies, [NodeDef.NPC_INTEL_TARGET], no_quests, &""))
	world.nodes.append(_node("07", "山脚村落", town, [&"gear_shop"], no_enemies, [NodeDef.NPC_SHOP], no_quests, &"material_small"))
	world.nodes.append(_node("17", "城镇偏街", town, [&"weapon_shop"], no_enemies, [NodeDef.NPC_SHOP], no_quests, &""))
	world.nodes.append(_node("18", "外围集市", town, [&"gear_shop"], no_enemies, [NodeDef.NPC_SHOP], no_quests, &""))

	# 野外：少量遭遇与资源，保留有意义的绕行
	world.nodes.append(_node("05", "城外官道", road, no_shops, [&"bandit", &"bandit"], no_npcs, no_quests, &"material_small"))
	world.nodes.append(_node("08", "山口", road, no_shops, [&"bandit"], no_npcs, no_quests, &"supply_small"))
	world.nodes.append(_node("09", "河岸", road, no_shops, [&"bandit"], no_npcs, no_quests, &"material_small"))
	world.nodes.append(_node("10", "废弃渡口", road, no_shops, [&"bandit"], no_npcs, no_quests, &"material_small"))

	# 土匪节点集群
	world.nodes.append(_node("11", "土匪前哨", camp, no_shops, [&"bandit"], no_npcs, no_quests, &"supply_small"))
	world.nodes.append(_node("12", "土匪营地", camp, no_shops, [&"camp_blade"], no_npcs, no_quests, &"material_small"))
	world.nodes.append(_node("13", "土匪侧营", camp, no_shops, [&"bandit"], no_npcs, no_quests, &"material_small"))
	world.nodes.append(_node("14", "后山据点", camp, no_shops, [&"camp_blade"], no_npcs, no_quests, &"material_small"))
	world.nodes.append(_node("15", "头子所在主寨", camp, no_shops, [&"bandit_chief"], no_npcs, no_quests, &"", true))
	world.nodes.append(_node("16", "土匪仓场", camp, no_shops, [&"camp_blade"], no_npcs, no_quests, &"material_small"))

	# 双向连接（样本地图）
	var pairs := [
		["01", "02"], ["01", "03"], ["02", "03"], ["02", "04"], ["03", "05"], ["03", "17"],
		["04", "07"], ["05", "06"], ["05", "09"], ["06", "08"], ["07", "08"], ["08", "11"],
		["08", "13"], ["09", "10"], ["10", "13"], ["11", "12"], ["12", "15"], ["12", "16"],
		["13", "14"], ["14", "15"], ["15", "16"], ["17", "18"],
	]
	for p in pairs:
		if p[0] == "08" and p[1] == "11":
			world.connections.append(_conn(p[0], p[1], &"mountain_guard"))
		else:
			world.connections.append(_conn(p[0], p[1]))

	# 任务
	var main := QuestDef.new()
	main.quest_id = &"main_kill_chief"
	main.display_name = "寻找并击杀土匪头子"
	main.is_main = true
	main.objective_type = QuestDef.OBJECTIVE_KILL_ENEMY
	main.target_enemy_id = &"bandit_chief"
	main.target_node_id = "15"
	main.reward_money = 24
	main.reward_id = &"reward_main_chief"
	main.claim_mode = QuestDef.CLAIM_AUTO
	main.description = "区域与准确节点开局均不揭示，可打听或实地发现"
	world.quests.append(main)

	var side_challenge := QuestDef.new()
	side_challenge.quest_id = &"side_challenge"
	side_challenge.display_name = "挑战武者"
	side_challenge.objective_type = QuestDef.OBJECTIVE_CHALLENGE
	side_challenge.target_enemy_id = &"bandit"
	side_challenge.target_node_id = "02"
	side_challenge.reward_money = 6
	side_challenge.reward_id = &"reward_side_challenge"
	side_challenge.claim_mode = QuestDef.CLAIM_AUTO
	side_challenge.retroactive = true
	side_challenge.description = "胜后现场领取 6"
	world.quests.append(side_challenge)

	var side_road := QuestDef.new()
	side_road.quest_id = &"side_road_bandit"
	side_road.display_name = "击杀路匪"
	side_road.objective_type = QuestDef.OBJECTIVE_KILL_ENEMY
	side_road.target_enemy_id = &"bandit"
	side_road.target_node_id = "05"
	side_road.reward_money = 6
	side_road.reward_id = &"reward_side_road_bandit"
	side_road.claim_mode = QuestDef.CLAIM_NPC
	side_road.claim_node_id = "01"
	side_road.retroactive = true
	side_road.description = "回 01 委托 NPC 领取 6"
	world.quests.append(side_road)

	_save(world, "res://data/worlds/wudao_01.tres")


func _save_manifest() -> void:
	var manifest := {
		"content_version": CONTENT_VERSION,
		"engine_version": "4.7.2-stable",
		"generated_by": "tools/build_content.gd",
		"sources": [
			"游戏最小战斗与经济方案.md 第 3/4/5/6 节",
			"游戏可玩原型技术方案.md 第 9/10/12 节",
			"游戏单局推演.md 第 3 节",
		],
		"prototype_defaults": [
			"商店候选池与类别权重",
			"节点内容配置（商店/敌人/容器/情报 NPC 的分布）",
			"入口可选弱敌",
			"容器内容表",
		],
	}
	var f := FileAccess.open("res://data/content_manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	_written += 1
