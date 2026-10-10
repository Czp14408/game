class_name RunState
extends RefCounted
## 一次试炼的全部可变状态。场景关闭不能重置它。
## 依据：游戏可玩原型技术方案.md 第 5 节；游戏核心规则定稿.md 第 1/5 节。

const STATE_RUNNING := &"running"
const STATE_STAGE_COMPLETE := &"stage_complete"
const STATE_FAILED := &"failed"
const STATE_SURRENDERED := &"surrendered"

const BAR_CAPACITY := 10
const INVENTORY_CAPACITY := 10
const BASE_MAX_HP := 100.0
const MAX_DEFEATS := 3
const START_MONEY := 30

var catalog: ContentCatalog
var rng: RandomService

## --- 玩家 ---
var current_hp: float = BASE_MAX_HP
var max_hp: float = BASE_MAX_HP
var profession: StringName = &""
var bloodline: StringName = &""
var money: int = START_MONEY
var defeats: int = 0
var battle_bar: Array[ItemInstance] = []
var inventory: Array[ItemInstance] = []
var skills: Dictionary = {}      # StringName -> SkillState

## --- 世界进度 ---
var world_id: StringName = &""
var current_node_id: String = ""
var current_stage: int = 1
var paid_node_count: int = 0
var node_states: Dictionary = {}    # node_id -> NodeState
var known_intel: Dictionary = {}    # intel key -> true
var quest_states: Dictionary = {}   # quest_id -> QuestState
var claimed_rewards: Dictionary = {}# reward_id -> true
var pending_quest_items: Dictionary = {} # reward_id -> ItemInstance; capacity failure does not reroll
var submitted_battles: Dictionary = {} # battle_id -> true
var main_completed: bool = false
var returned_to_deity: bool = false
var stage_opponent: Dictionary = {} # 生成的阶段对手（固定）
## 已完成的目标标记："node_id/enemy_template" -> true；用于支线追认
var objective_flags: Dictionary = {}
var state: StringName = STATE_RUNNING

## --- 内部 ---
var _instances: Dictionary = {}   # instance_id -> ItemInstance
var _seq: int = 0
var _battle_seq: int = 0


static func create(p_catalog: ContentCatalog, p_rng: RandomService) -> RunState:
	var r := RunState.new()
	r.catalog = p_catalog
	r.rng = p_rng
	return r


func next_seq() -> int:
	_seq += 1
	return _seq


func next_battle_id(prefix: String) -> String:
	_battle_seq += 1
	return "%s_%03d" % [prefix, _battle_seq]


# ---------------------------------------------------------------------------
# 实例登记
# ---------------------------------------------------------------------------

func new_instance(def_id: StringName, quality: int, origin_node: String = "") -> ItemInstance:
	var it := ItemInstance.make(def_id, quality, next_seq())
	it.origin_node = origin_node
	_instances[it.instance_id] = it
	return it


func register_instance(it: ItemInstance) -> void:
	_instances[it.instance_id] = it


func instance(instance_id: String) -> ItemInstance:
	return _instances.get(instance_id)


func is_held(instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false
	var it: ItemInstance = _instances[instance_id]
	return it.location == ItemInstance.LOC_BATTLE or it.location == ItemInstance.LOC_INVENTORY


func all_instances() -> Array:
	return _instances.values()


# ---------------------------------------------------------------------------
# 容量
# ---------------------------------------------------------------------------

func bar_used() -> int:
	var total := 0
	for it in battle_bar:
		total += it.size(catalog)
	return total


func inventory_used() -> int:
	var total := 0
	for it in inventory:
		total += it.size(catalog)
	return total


func bar_free() -> int:
	return BAR_CAPACITY - bar_used()


func inventory_free() -> int:
	return INVENTORY_CAPACITY - inventory_used()


## 用操作后的总占用校验，不要求交换时额外临时空格
func fits_after(bar: Array, inv: Array) -> bool:
	var b := 0
	for it in bar:
		b += (it as ItemInstance).size(catalog)
	var i := 0
	for it in inv:
		i += (it as ItemInstance).size(catalog)
	return b <= BAR_CAPACITY and i <= INVENTORY_CAPACITY


# ---------------------------------------------------------------------------
# 生命与职业血统
# ---------------------------------------------------------------------------

func apply_traits() -> void:
	# 职业与血统都要计入（此前只读 bloodline，导致职业侧的 max_hp_flat 被静默忽略）。
	# 复用 trait_value()，与 weapon_damage_flat / heal_computed_flat 的取法保持一致。
	max_hp = BASE_MAX_HP + trait_value(TraitDef.EFFECT_MAX_HP_FLAT)
	current_hp = max_hp


func trait_value(effect_type: StringName) -> float:
	var total := 0.0
	var p := catalog.trait_by_id(profession)
	if p != null and p.effect_type == effect_type:
		total += p.effect_amount
	var b := catalog.trait_by_id(bloodline)
	if b != null and b.effect_type == effect_type:
		total += b.effect_amount
	return total


func skill_quality(skill_id: StringName) -> int:
	var s: SkillState = skills.get(skill_id)
	return -1 if s == null else s.quality


func set_hp(value: float) -> void:
	current_hp = clampf(value, 0.0, max_hp)


func add_money(amount: int) -> void:
	money += amount


func spend_money(amount: int) -> bool:
	if amount > money or amount < 0:
		return false
	money -= amount
	return true


func register_defeat() -> void:
	defeats += 1
	if defeats >= MAX_DEFEATS:
		state = STATE_FAILED


## 未结束试炼时战败恢复：恢复至当前有效最大生命的 100%
func revive_after_defeat() -> void:
	if state == STATE_RUNNING:
		current_hp = max_hp


func is_running() -> bool:
	return state == STATE_RUNNING


func node_state(node_id: String) -> NodeState:
	if not node_states.has(node_id):
		var ns := NodeState.new()
		ns.node_id = node_id
		node_states[node_id] = ns
	return node_states[node_id]


func quest_state(quest_id: StringName) -> QuestState:
	if not quest_states.has(quest_id):
		var qs := QuestState.new()
		qs.quest_id = quest_id
		quest_states[quest_id] = qs
	return quest_states[quest_id]


## 试炼结束：清除本次试炼获得的一切，不带入下一次试炼
func end_trial(new_state: StringName) -> void:
	state = new_state
	_instances.clear()
	battle_bar.clear()
	inventory.clear()
	skills.clear()


func summary() -> Dictionary:
	return {
		"state": String(state),
		"hp": current_hp,
		"max_hp": max_hp,
		"money": money,
		"defeats": defeats,
		"profession": String(profession),
		"bloodline": String(bloodline),
		"current_node": current_node_id,
		"paid_nodes": paid_node_count,
		"main_completed": main_completed,
		"bar": _items_summary(battle_bar),
		"inventory": _items_summary(inventory),
		"skills": skills.keys().map(func(k): return ["%s:%d" % [k, skills[k].quality]]),
	}


func _items_summary(arr: Array) -> Array:
	var out := []
	for it in arr:
		out.append(["%s:q%d:+%.1f" % [it.definition_id, it.quality, it.trial_growth]])
	return out
