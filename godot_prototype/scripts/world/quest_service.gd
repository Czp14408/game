class_name QuestService
extends RefCounted
## 主线、支线、自动与 NPC 领奖。每项奖励最多领取一次（reward_id 防重复）。
## 依据：游戏核心规则定稿.md 第 1/6 节；游戏一阶段原型需求.md 首版支线目标追认。

var catalog: ContentCatalog
var recorder: SessionRecorder


func _init(p_catalog: ContentCatalog = null) -> void:
	catalog = p_catalog


func world(state: RunState) -> WorldDef:
	return catalog.worlds.get(state.world_id)


## 接取任务。追认规则：接取前已完成的指定目标直接进入完成状态。
func accept(state: RunState, quest_id: StringName) -> OperationResult:
	var w := world(state)
	if w == null:
		return OperationResult.fail("世界定义缺失")
	var def := w.quest_by_id(quest_id)
	if def == null:
		return OperationResult.fail("任务不存在")
	var qs := state.quest_state(quest_id)
	if qs.status != QuestState.STATUS_LOCKED:
		return OperationResult.fail("任务已接取")
	qs.status = QuestState.STATUS_ACCEPTED
	_log(state, "quest_accept", {"quest": String(quest_id)})
	if def.retroactive and _objective_satisfied(state, def):
		qs.status = QuestState.STATUS_COMPLETED
		_log(state, "quest_retroactive_complete", {"quest": String(quest_id)})
		return OperationResult.ok({"accepted": true, "completed": true})
	return OperationResult.ok({"accepted": true, "completed": false})


## 战斗胜利后推进任务目标
func notify_enemy_defeated(state: RunState, enemy_template_id: StringName, node_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.objective_flags["%s/%s" % [node_id, enemy_template_id]] = true
	var w := world(state)
	if w == null:
		return events
	for def in w.quests:
		if def.target_enemy_id != enemy_template_id:
			continue
		if def.target_node_id != "" and def.target_node_id != node_id:
			continue
		var qs := state.quest_state(def.quest_id)
		if qs.is_done():
			continue
		if qs.status != QuestState.STATUS_ACCEPTED:
			continue
		qs.status = QuestState.STATUS_COMPLETED
		events.append({"quest_id": def.quest_id, "display_name": def.display_name})
		_log(state, "quest_complete", {"quest": String(def.quest_id), "node": node_id})
		if def.claim_mode == QuestDef.CLAIM_AUTO:
			var r := claim(state, def.quest_id)
			if r.success:
				events.append({"auto_claimed": def.quest_id, "money": def.reward_money})
	return events


## 完成主线后的处理：开放回归
func _check_main(state: RunState) -> void:
	var w := world(state)
	if w == null:
		return
	for def in w.quests:
		if not def.is_main:
			continue
		var qs := state.quest_state(def.quest_id)
		if qs.is_claimed():
			state.main_completed = true


## 领奖：每项奖励最多一次
func claim(state: RunState, quest_id: StringName) -> OperationResult:
	var w := world(state)
	if w == null:
		return OperationResult.fail("世界定义缺失")
	var def := w.quest_by_id(quest_id)
	if def == null:
		return OperationResult.fail("任务不存在")
	var qs := state.quest_state(quest_id)
	if qs.status != QuestState.STATUS_COMPLETED:
		return OperationResult.fail("任务尚未完成")
	if state.claimed_rewards.has(def.reward_id):
		return OperationResult.fail("该奖励已领取")
	if def.claim_mode == QuestDef.CLAIM_NPC and state.current_node_id != def.claim_node_id:
		return OperationResult.fail("需回到 %s 号节点向委托 NPC 领取" % def.claim_node_id)

	state.claimed_rewards[def.reward_id] = true
	qs.status = QuestState.STATUS_CLAIMED
	state.add_money(def.reward_money)
	if def.is_main:
		state.main_completed = true
	_log(state, "quest_claim", {
		"quest": String(quest_id),
		"reward_id": String(def.reward_id),
		"money": def.reward_money,
	})
	return OperationResult.ok({"money": def.reward_money, "reward_id": String(def.reward_id)})


func _objective_satisfied(state: RunState, def: QuestDef) -> bool:
	var key := "%s/%s" % [def.target_node_id, def.target_enemy_id]
	return state.objective_flags.has(key)


func _log(state: RunState, kind: String, data: Dictionary) -> void:
	if recorder != null:
		recorder.record_event(kind, data)
