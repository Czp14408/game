class_name CombatActor
extends RefCounted
## 战斗一方的运行状态。玩家与敌人共用同一结构。

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

var side: int = SIDE_PLAYER
var display_name: String = ""
var max_hp: float = 100.0
var hp: float = 100.0
var shield: float = 0.0

## 持续伤害层：每层来自一个施加来源，用于统计归属
var burn_stacks: Array[Dictionary] = []    # {source: String, layers: float}
var poison_stacks: Array[Dictionary] = []

var profession: StringName = &""
var bloodline: StringName = &""
var skills: Dictionary = {}        # StringName -> quality

var items: Array[BattleItemState] = []

## 被动修正
var weapon_damage_flat: float = 0.0
var heal_computed_flat: float = 0.0
var heal_on_weapon_use: float = 0.0

## --- 统计 ---
var heal_computed: float = 0.0
var heal_actual: float = 0.0
var shield_gained: float = 0.0
var storm_damage: float = 0.0
var damage_attack: float = 0.0
var damage_burn: float = 0.0
var damage_poison: float = 0.0
var damage_taken_shield: float = 0.0
var damage_taken_hp: float = 0.0
## 非物品来源的统计（职业、血统、独立技能），不重复累加为额外伤害
var trait_stats: Dictionary = {}
var skill_stats: Dictionary = {}

var hp_limit_delta_pending: float = 0.0


func is_alive() -> bool:
	return hp > 0.0


func total_burn() -> float:
	var t := 0.0
	for s in burn_stacks:
		t += float(s["layers"])
	return t


func total_poison() -> float:
	var t := 0.0
	for s in poison_stacks:
		t += float(s["layers"])
	return t


func add_stack(list: Array, source_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	for s in list:
		if s["source"] == source_id:
			s["layers"] = float(s["layers"]) + amount
			return
	list.append({"source": source_id, "layers": amount})


## 灼烧每跳后减少 1 层，从最早的来源开始衰减
func decay_burn_one_layer() -> void:
	for s in burn_stacks:
		if float(s["layers"]) > 0.0:
			s["layers"] = float(s["layers"]) - 1.0
			break


func skill_level(skill_id: StringName) -> int:
	return int(skills.get(skill_id, -1))


func add_trait_stat(key: String, amount: float) -> void:
	trait_stats[key] = float(trait_stats.get(key, 0.0)) + amount


func add_skill_stat(key: String, amount: float) -> void:
	skill_stats[key] = float(skill_stats.get(key, 0.0)) + amount
