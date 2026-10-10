class_name EncounterService
extends RefCounted
## 战前输入、战后奖励与失败归位。遭遇从世界状态读写，不以节点实例存活为依据。
## 依据：游戏可玩原型技术方案.md 第 7/12/13 节；游戏最小战斗与经济方案.md 第 6 节。

const WORLD_BATTLE_REWARD := 6
const DROP_MATERIAL_CHANCE := 0.3

var catalog: ContentCatalog
var rng: RandomService
var recorder: SessionRecorder
var quests: QuestService
var inventory: InventoryService
## 三路线回放/随机游玩的显式掉落输入：{"node_id": "material"|"config"|物品ID}
var drop_override: Dictionary = {}
## 回放用的阶段对手显式输入：{"template": StringName, "extra": StringName}
var stage_override: Dictionary = {}


func _init(p_catalog: ContentCatalog = null) -> void:
	catalog = p_catalog
	inventory = InventoryService.new(p_catalog)


func bind(p_rng: RandomService, p_quests: QuestService, p_recorder: SessionRecorder) -> void:
	rng = p_rng
	quests = p_quests
	recorder = p_recorder


func encounter_key(node_id: String, template_id: StringName) -> String:
	return "%s>%s#0" % [node_id, template_id]


func ensure(state: RunState, node_id: String, key: String) -> EncounterState:
	var ns := state.node_state(node_id)
	var es: EncounterState = ns.encounters.get(key)
	if es != null:
		return es
	var es2 := EncounterState.new()
	es2.encounter_key = key
	es2.node_id = node_id
	es2.enemy_template_id = _template_of(key)
	es2.is_guard = key.ends_with("#guard")
	ns.encounters[key] = es2
	return es2


func _template_of(key: String) -> StringName:
	var parts := key.split(">")
	if parts.size() < 2:
		return &""
	return StringName(parts[1].split("#")[0])


# ---------------------------------------------------------------------------
# 战前
# ---------------------------------------------------------------------------

func player_spec(state: RunState) -> Dictionary:
	var items := []
	for it in state.battle_bar:
		items.append({
			"definition_id": it.definition_id,
			"quality": it.quality,
			"trial_growth": it.trial_growth,
			"instance_id": it.instance_id,
		})
	var skills := {}
	for k in state.skills.keys():
		skills[k] = (state.skills[k] as SkillState).quality
	return {
		"side": CombatActor.SIDE_PLAYER,
		"display_name": "玩家",
		"max_hp": state.max_hp,
		"hp": state.current_hp,
		"profession": state.profession,
		"bloodline": state.bloodline,
		"skills": skills,
		"items": items,
	}


func enemy_spec_from_encounter(state: RunState, es: EncounterState) -> Dictionary:
	var def := catalog.enemy(es.enemy_template_id)
	if def == null:
		return {}
	var items := []
	for g in def.equipment:
		items.append({
			"definition_id": g.definition_id,
			"quality": g.quality,
			"extra_value": g.extra_value,
		})
	var skills := {}
	for g in def.skills:
		skills[g.definition_id] = g.quality
	return {
		"side": CombatActor.SIDE_ENEMY,
		"display_name": def.display_name,
		"max_hp": def.max_hp,
		"hp": def.max_hp,
		"skills": skills,
		"items": items,
	}


func begin_battle(state: RunState, es: EncounterState, battle_prefix: String) -> CombatEngine:
	var battle_id := state.next_battle_id(battle_prefix)
	es.battle_id = battle_id
	var engine := CombatEngine.new()
	engine.catalog = catalog
	engine.rng = rng
	var player := CombatEngine.build_actor(catalog, player_spec(state))
	var enemy := CombatEngine.build_actor(catalog, enemy_spec_from_encounter(state, es))
	engine.begin(player, enemy, battle_id, "battle/%s" % battle_id)
	return engine


func begin_stage_battle(state: RunState) -> CombatEngine:
	var battle_id := state.next_battle_id("stage")
	var engine := CombatEngine.new()
	engine.catalog = catalog
	engine.rng = rng
	var player := CombatEngine.build_actor(catalog, player_spec(state))
	var set_ := catalog.stage_set(&"stage_01")
	var equipment: Array = []
	for g in state.stage_opponent.get("equipment", []):
		equipment.append(g)
	var enemy := CombatEngine.build_stage_opponent(catalog, set_, equipment, str(state.stage_opponent.get("display_name", "阶段试炼者")))
	engine.begin(player, enemy, battle_id, "battle/%s" % battle_id)
	state.stage_opponent["battle_id"] = battle_id
	return engine


# ---------------------------------------------------------------------------
# 战后结算
# ---------------------------------------------------------------------------

## 返回结算摘要。battle_id 已提交标记保证幂等。
func settle(state: RunState, es: EncounterState, engine: CombatEngine) -> Dictionary:
	var result := engine.result()
	es.last_result = result
	var summary := {
		"battle_id": result.battle_id,
		"outcome": String(result.outcome),
		"time": result.time_seconds,
		"player_hp": result.player_hp,
		"money_gain": 0,
		"drops": [],
		"duplicate": false,
	}

	# 战斗完成以 battle_id 为防重复依据
	if state.submitted_battles.has(result.battle_id):
		summary["duplicate"] = true
		return summary

	state.set_hp(result.player_hp)

	if not result.winner_is_player():
		state.submitted_battles[result.battle_id] = true
		state.register_defeat()
		state.revive_after_defeat()
		_log(state, "battle_failed", {
			"encounter": es.encounter_key,
			"time": result.time_seconds,
			"defeats": state.defeats,
		})
		return summary

	state.submitted_battles[result.battle_id] = true
	es.defeated = true
	es.reward_claimed = true

	# 普通世界战斗：货币 + 随机掉落（阶段 Boss 无奖励）
	if es.enemy_template_id != &"" and _is_world_encounter(es):
		state.add_money(WORLD_BATTLE_REWARD)
		summary["money_gain"] = WORLD_BATTLE_REWARD
		_generate_drops(state, es, summary)

	var quest_events: Array[Dictionary] = []
	if quests != null:
		quest_events = quests.notify_enemy_defeated(state, es.enemy_template_id, es.node_id)
	summary["quests"] = quest_events
	_log(state, "battle_won", {
		"encounter": es.encounter_key,
		"time": result.time_seconds,
		"hp": result.player_hp,
		"money_gain": summary["money_gain"],
		"drops": summary["drops"],
		"quests": quest_events,
	})
	return summary


func _is_world_encounter(es: EncounterState) -> bool:
	return not es.node_id.begins_with("__")


## 随机奖励：70% 从实际配置中可掉条目等概率抽取，30% 为一份材料；无合法条目改为材料
func _generate_drops(state: RunState, es: EncounterState, summary: Dictionary) -> void:
	var enemy := catalog.enemy(es.enemy_template_id)
	if enemy == null:
		return
	var scope := "drop/%s" % es.encounter_key
	var forced: String = str(drop_override.get(es.node_id, ""))
	# 显式输入：material / config（从实际配置随机）/ 具体物品 definition_id（回放用）
	if forced != "" and forced != "material" and forced != "config" and catalog.item(StringName(forced)) != null:
		var fixed_item := state.new_instance(StringName(forced), 0, es.node_id)
		fixed_item.location = ItemInstance.LOC_NONE
		es.pending_drops.append(fixed_item)
		summary["drops"].append({"kind": "item", "definition_id": forced, "quality": 0, "forced": true})
		return
	var branch := ""
	if forced == "material":
		branch = "material"
	elif forced == "equipment":
		branch = "config"
	else:
		branch = "material" if rng.rand_float(scope) < DROP_MATERIAL_CHANCE else "config"

	var entries := enemy.resolved_drop_entries()
	var extra_rules := catalog.reward_rules("drop",String(enemy.template_id))
	if branch == "config" and entries.is_empty() and extra_rules.is_empty():
		branch = "material"

	if branch == "material":
		var mat := state.new_instance(&"scrap_material", 0, es.node_id)
		mat.location = ItemInstance.LOC_NONE
		es.pending_drops.append(mat)
		summary["drops"].append({"kind": "material", "definition_id": "scrap_material"})
		return

	var grant: GrantDef
	if extra_rules.is_empty():
		grant = entries[rng.rand_index(scope,entries.size())]
	else:
		var weights: Array = []
		for entry in entries: weights.append(1.0)
		for rule in extra_rules: weights.append(float(rule["weight"]))
		var idx := rng.pick_weighted(scope,weights)
		if idx < entries.size():
			grant = entries[idx]
		else:
			var chosen: Dictionary = extra_rules[idx-entries.size()]
			grant = GrantDef.new()
			grant.definition_id = StringName(chosen["item"])
			grant.quality = int(chosen["min_quality"]) + rng.rand_index(scope,int(chosen["max_quality"])-int(chosen["min_quality"])+1)
			if catalog.item(grant.definition_id).fixed_base_price>=0:grant.quality=0
	if grant.is_skill:
		es.pending_skill = {"skill_id": grant.definition_id, "quality": grant.quality}
		summary["drops"].append({"kind": "skill", "definition_id": String(grant.definition_id), "quality": grant.quality})
	else:
		var it := state.new_instance(grant.definition_id, grant.quality, es.node_id)
		it.location = ItemInstance.LOC_NONE
		es.pending_drops.append(it)
		summary["drops"].append({"kind": "item", "definition_id": String(grant.definition_id), "quality": grant.quality})


## 技能掉落必须当场决定学习或放弃；放弃后不能通过重访重新领取
func resolve_skill_drop(state: RunState, es: EncounterState, learn: bool, economy: EconomyService) -> OperationResult:
	if es.pending_skill.is_empty():
		return OperationResult.fail("本场没有待决策的技能掉落")
	var skill_id: StringName = es.pending_skill["skill_id"]
	var quality: int = es.pending_skill["quality"]
	es.pending_skill = {}
	if not learn:
		_log(state, "skill_declined", {"skill": String(skill_id)})
		return OperationResult.ok({"learned": false})
	if economy == null:
		return OperationResult.fail("经济服务缺失")
	var r := economy.learn_skill(state, skill_id, quality)
	_log(state, "skill_drop_resolved", {"skill": String(skill_id), "quality": quality, "success": r.success})
	return r


## 拾取待拾取掉落（容量不足时保留）
func pickup_pending(state: RunState, es: EncounterState) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var remain: Array = []
	for it in es.pending_drops:
		var r := inventory.pickup(state, it)
		if r.success:
			results.append({"instance_id": it.instance_id, "ok": true})
		else:
			results.append({"instance_id": it.instance_id, "ok": false, "reason": r.reason})
			remain.append(it)
	es.pending_drops = remain
	return results


# ---------------------------------------------------------------------------
# 阶段对手生成（回归、进入整备时生成一次并保存）
# ---------------------------------------------------------------------------

func ensure_stage_opponent(state: RunState) -> Dictionary:
	if not state.stage_opponent.is_empty():
		return state.stage_opponent
	var set_ := catalog.stage_set(&"stage_01")
	var scope := "stage/stage_01"
	var t_idx := rng.rand_index(scope, set_.templates.size())
	var e_idx := rng.rand_index(scope, set_.extra_pool.size())
	# 回放/测试的显式输入：固定模板与追加组件，不改变生成后的固定性
	if stage_override.has("template"):
		for i in set_.templates.size():
			if set_.templates[i].template_id == stage_override["template"]:
				t_idx = i
	if stage_override.has("extra"):
		for i in set_.extra_pool.size():
			if set_.extra_pool[i].definition_id == stage_override["extra"]:
				e_idx = i
	var tpl: StageTemplateDef = set_.templates[t_idx]
	var extra: GrantDef = set_.extra_pool[e_idx]
	var equipment: Array = []
	for g in tpl.equipment:
		equipment.append(g)
	equipment.append(extra)
	state.stage_opponent = {
		"template_id": String(tpl.template_id),
		"display_name": "%s＋%s" % [tpl.display_name, catalog.item_display(extra.definition_id)],
		"equipment": equipment,
		"max_hp": set_.max_hp,
	}
	_log(state, "stage_opponent_generated", {
		"template": String(tpl.template_id),
		"extra": String(extra.definition_id),
	})
	return state.stage_opponent


func settle_stage(state: RunState, engine: CombatEngine) -> Dictionary:
	var result := engine.result()
	var summary := {
		"battle_id": result.battle_id,
		"outcome": String(result.outcome),
		"time": result.time_seconds,
		"player_hp": result.player_hp,
		"duplicate": false,
	}
	if state.submitted_battles.has(result.battle_id):
		summary["duplicate"] = true
		return summary
	state.submitted_battles[result.battle_id] = true
	state.set_hp(result.player_hp)
	if result.winner_is_player():
		state.state = RunState.STATE_STAGE_COMPLETE
		_log(state, "stage_complete", {"time": result.time_seconds, "hp": result.player_hp})
	else:
		state.register_defeat()
		state.revive_after_defeat()
		_log(state, "stage_failed", {"time": result.time_seconds, "defeats": state.defeats})
	return summary


func _log(state: RunState, kind: String, data: Dictionary) -> void:
	if recorder != null:
		recorder.record_event(kind, data)
