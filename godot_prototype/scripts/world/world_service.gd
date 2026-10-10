class_name WorldService
extends RefCounted
## 节点进入、费用阶梯、状态保留与情报。不直接执行伤害。
## 依据：游戏可玩原型技术方案.md 第 9/10 节；游戏核心规则定稿.md 第 2 节。

const ENTRY_FEE_BASE := 2   # 第 k 个其他新节点首次进入费为 k+1

var catalog: ContentCatalog
var recorder: SessionRecorder
var rng: RandomService


func _init(p_catalog: ContentCatalog = null) -> void:
	catalog = p_catalog


func world(state: RunState) -> WorldDef:
	return catalog.worlds.get(state.world_id)


# ---------------------------------------------------------------------------
# 费用与进入
# ---------------------------------------------------------------------------

func is_entered(state: RunState, node_id: String) -> bool:
	return state.node_state(node_id).entered


## 免费入口节点、已付费节点重访均免费
func entry_fee(state: RunState, node_id: String) -> int:
	var w := world(state)
	if w == null:
		return 0
	if node_id == w.entry_node_id:
		return 0
	if state.node_state(node_id).entered:
		return 0
	return state.paid_node_count + ENTRY_FEE_BASE


func next_fee_preview(state: RunState) -> int:
	return state.paid_node_count + ENTRY_FEE_BASE


func can_travel(state: RunState, to_node: String) -> OperationResult:
	# 回归后不可再进入武道世界（规则由服务层裁决，不依赖界面导航是否暴露入口）
	if state.returned_to_deity:
		return OperationResult.fail("已回归主神空间，不可再进入武道世界")
	var w := world(state)
	if w == null:
		return OperationResult.fail("世界定义缺失")
	if w.node_by_id(to_node) == null:
		return OperationResult.fail("节点不存在")
	# 世界进入与首个落脚节点免费，不需要连接关系
	if state.current_node_id == "":
		if to_node != w.entry_node_id:
			return OperationResult.fail("首次只能进入免费入口节点")
		return OperationResult.ok({"fee": 0, "guarded": false})
	if to_node == state.current_node_id:
		return OperationResult.fail("已在当前节点")
	if not w.neighbors(state.current_node_id).has(to_node):
		return OperationResult.fail("节点之间没有连接")
	var conn := w.connection_between(state.current_node_id, to_node)
	if is_connection_blocked(state, state.current_node_id, to_node):
		return OperationResult.fail("连接被守路者封锁，需先击败守路者")
	var fee := entry_fee(state, to_node)
	if fee > state.money:
		return OperationResult.fail("余额不足（本次进入需要 %d，现有 %d）" % [fee, state.money])
	return OperationResult.ok({"fee": fee, "guarded": conn.guard_enemy_id != &""})


## 首次进入其他新节点：先显示费用、验证余额，再一次性扣款、标记已付费并加载小地图
func travel(state: RunState, to_node: String) -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	var check := can_travel(state, to_node)
	if not check.success:
		return check
	var fee: int = check.data["fee"]
	var ns := state.node_state(to_node)
	if fee > 0:
		if not state.spend_money(fee):
			return OperationResult.fail("扣款失败，未进入节点")
		state.paid_node_count += 1
		ns.fee_amount = fee
	ns.entered = true
	ns.fee_paid = ns.fee_paid or fee > 0
	ns.discovered = true
	state.current_node_id = to_node
	_log(state, "node_enter", {
		"node": to_node,
		"fee": fee,
		"paid_nodes": state.paid_node_count,
		"money": state.money,
	})
	return OperationResult.ok({"fee": fee, "node": to_node})


# ---------------------------------------------------------------------------
# 守路条件
# ---------------------------------------------------------------------------

func guard_encounter_key(conn: ConnectionDef) -> String:
	return "%s>%s#guard" % [conn.node_a, conn.guard_enemy_id]


## 未击败守路者时，对应连接不可通行
func is_connection_blocked(state: RunState, from_node: String, to_node: String) -> bool:
	var w := world(state)
	if w == null:
		return false
	var conn := w.connection_between(from_node, to_node)
	if conn == null or conn.guard_enemy_id == &"":
		return false
	var guard_node := conn.node_a
	var es := state.node_state(guard_node).encounter(guard_encounter_key(conn))
	if es == null:
		return true
	return not es.defeated


func reveal_guard_reason(state: RunState, from_node: String, to_node: String) -> bool:
	var w := world(state)
	if w == null:
		return false
	var conn := w.connection_between(from_node, to_node)
	if conn == null or conn.guard_enemy_id == &"":
		return false
	var ns := state.node_state(conn.node_a)
	var key := "%s|%s" % [conn.node_a, conn.node_b]
	if ns.guard_revealed.has(key):
		return true
	ns.guard_revealed[key] = true
	_log(state, "guard_revealed", {"connection": key, "guard": String(conn.guard_enemy_id)})
	return true


## 节点内的敌人清单：节点自身配置 + 该节点出发连接上的守路者
func node_enemy_keys(state: RunState, node_id: String) -> Array[String]:
	var w := world(state)
	var out: Array[String] = []
	if w == null:
		return out
	var nd := w.node_by_id(node_id)
	if nd == null:
		return out
	var counts := {}
	for tpl in nd.enemies:
		var idx: int = counts.get(tpl, 0)
		counts[tpl] = idx + 1
		out.append("%s>%s#%d" % [node_id, tpl, idx])
	for conn in w.connections:
		if conn.guard_enemy_id == &"" or conn.node_a != node_id:
			continue
		out.append(guard_encounter_key(conn))
	return out


func enemy_template_from_key(key: String) -> StringName:
	var parts := key.split(">")
	if parts.size() < 2:
		return &""
	var rest := parts[1].split("#")
	return StringName(rest[0])


# ---------------------------------------------------------------------------
# NPC 服务
# ---------------------------------------------------------------------------

func talk(state: RunState, node_id: String, service: StringName, quest_service: QuestService) -> OperationResult:
	match service:
		NodeDef.NPC_INTEL_AREA:
			state.known_intel["bandit_area"] = true
			return OperationResult.ok({"text": "路人提到：土匪在城外的山口与营地一带活动。", "intel": "bandit_area"})
		NodeDef.NPC_INTEL_TARGET:
			state.known_intel["chief_node"] = true
			state.known_intel["bandit_area"] = true
			return OperationResult.ok({
				"text": "驿卒说：头子就在 15 号主寨，用重锤，出手狠但间隔长。",
				"intel": "chief_node",
			})
		NodeDef.NPC_QUEST_CHALLENGE:
			return _quest_npc(state, &"side_challenge", quest_service,
				"武师邀你在本街区比试一场，胜后现场领奖。", "武师认下你此前的胜绩，当场付了 6。")
		NodeDef.NPC_QUEST_SIDE:
			return _quest_npc(state, &"side_road_bandit", quest_service,
				"委托人请你去 05 号官道除掉路匪，回来领 6。", "委托人听说官道路匪已经死了，付了 6。")
		NodeDef.NPC_SHOP:
			return OperationResult.ok({"text": "商人愿意收售货物。"})
	return OperationResult.fail("该 NPC 暂无可用服务")


## 任务 NPC：未接取则接取（追认接取前已完成的目标）；已完成则尝试领奖
func _quest_npc(state: RunState, quest_id: StringName, quest_service: QuestService, accept_text: String, claim_text: String) -> OperationResult:
	if quest_service == null:
		return OperationResult.fail("任务服务缺失")
	var qs := state.quest_state(quest_id)
	if qs.status == QuestState.STATUS_CLAIMED:
		return OperationResult.ok({"text": "这件事已经结清了。"})
	if qs.status == QuestState.STATUS_COMPLETED:
		var c := quest_service.claim(state, quest_id)
		if not c.success:
			return OperationResult.fail(c.reason)
		return OperationResult.ok({"text": claim_text, "money": c.data.get("money", 0), "claimed": true})
	if qs.status == QuestState.STATUS_LOCKED:
		var a := quest_service.accept(state, quest_id)
		if not a.success:
			return OperationResult.fail(a.reason)
		if bool(a.data.get("completed", false)):
			var c2 := quest_service.claim(state, quest_id)
			if c2.success:
				return OperationResult.ok({"text": claim_text, "money": c2.data.get("money", 0), "claimed": true})
		return OperationResult.ok({"text": accept_text, "accepted": true})
	return OperationResult.ok({"text": "这件事你已经在办了。"})


# ---------------------------------------------------------------------------
# 容器：使用有限内容表，开一次生成一次，未拾取实物留在节点
# ---------------------------------------------------------------------------

const CONTAINER_TABLE_MATERIAL := &"material_small"
const CONTAINER_TABLE_SUPPLY := &"supply_small"


func container_keys(state: RunState, node_id: String) -> Array[String]:
	var w := world(state)
	var out: Array[String] = []
	if w == null:
		return out
	var nd := w.node_by_id(node_id)
	if nd == null or not nd.has_container:
		return out
	out.append("%s#c0" % node_id)
	return out


func open_container(state: RunState, node_id: String, container_key: String) -> OperationResult:
	var ns := state.node_state(node_id)
	var rec: Dictionary = ns.containers.get(container_key, {})
	if bool(rec.get("opened", false)):
		return OperationResult.ok({"already": true, "drops": rec.get("drops", [])})
	var w := world(state)
	var nd := w.node_by_id(node_id)
	var table: StringName = nd.container_table if nd != null else CONTAINER_TABLE_MATERIAL
	var drops: Array = []
	var scope := "container/%s/%s" % [node_id, container_key]
	match table:
		CONTAINER_TABLE_SUPPLY:
			var idx := rng.rand_index(scope, 2) if rng != null else 0
			drops.append(state.new_instance(&"scrap_material" if idx == 0 else &"recovery_draught", 0, node_id))
		_:
			drops.append(state.new_instance(&"scrap_material", 0, node_id))
	var extra := catalog.roll_reward("event",String(table),rng,scope + "/excel")
	if not extra.is_empty(): drops.append(state.new_instance(extra["id"],extra["quality"],node_id))
	for it in drops:
		(it as ItemInstance).location = ItemInstance.LOC_NONE
	ns.containers[container_key] = {"opened": true, "table": table, "drops": drops}
	_log(state, "container_opened", {"node": node_id, "key": container_key, "count": drops.size()})
	return OperationResult.ok({"already": false, "drops": drops})


# ---------------------------------------------------------------------------
# 回归
# ---------------------------------------------------------------------------

func can_return(state: RunState) -> OperationResult:
	if not state.main_completed:
		return OperationResult.fail("主线未完成，不能回归主神空间")
	if state.returned_to_deity:
		return OperationResult.fail("已回归，不能再返回该世界")
	return OperationResult.ok()


func return_to_deity(state: RunState) -> OperationResult:
	var r := can_return(state)
	if not r.success:
		return r
	state.returned_to_deity = true
	_log(state, "return_to_deity", {"money": state.money, "hp": state.current_hp})
	return OperationResult.ok()


func _log(state: RunState, kind: String, data: Dictionary) -> void:
	if recorder != null:
		recorder.record_event(kind, data)
