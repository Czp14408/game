class_name NodeCardService
extends RefCounted


func specs(state: RunState, catalog: ContentCatalog, world: WorldService, encounters: EncounterService) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var definition := world.world(state).node_by_id(state.current_node_id)
	for shop_id in definition.shop_ids:
		var shop := catalog.shop(shop_id)
		out.append({"kind": "shop", "key": "%s/%s" % [state.current_node_id, shop_id], "label": shop.display_name})
	for npc in definition.npc_services:
		var labels := {NodeDef.NPC_SHOP: "商人", NodeDef.NPC_INTEL_AREA: "路人", NodeDef.NPC_INTEL_TARGET: "驿卒", NodeDef.NPC_QUEST_CHALLENGE: "武师", NodeDef.NPC_QUEST_SIDE: "委托人"}
		out.append({"kind": "npc", "key": String(npc), "label": labels.get(npc, String(npc))})
	for key in world.container_keys(state, state.current_node_id):
		var opened := bool(state.node_state(state.current_node_id).containers.get(key, {}).get("opened", false))
		out.append({"kind": "container", "key": key, "label": "已开启容器" if opened else "容器", "done": opened})
	for key in world.node_enemy_keys(state, state.current_node_id):
		var encounter := encounters.ensure(state, state.current_node_id, key)
		var enemy := catalog.enemy(encounter.enemy_template_id)
		out.append({"kind": "enemy", "key": key, "label": enemy.display_name, "done": encounter.defeated})
	return out


func initialize(ns: NodeState, specs: Array[Dictionary]) -> void:
	if not ns.card_lanes.is_empty():
		return
	for spec in specs:
		if spec["kind"] == "exit":
			continue
		var id := "%s:%s" % [spec["kind"], spec["key"]]
		ns.scene_cards[id] = spec.duplicate(true)
		ns.card_lanes.append([id])
		if spec["kind"] == "container":
			var cover := "cover:%s" % spec["key"]
			ns.scene_cards[cover] = {"kind": "cover", "label": "杂物", "key": cover}
			ns.card_lanes[-1].append(cover)
	ns.card_lanes.append([])


func accessible(ns: NodeState, id: String) -> bool:
	for lane in ns.card_lanes:
		if not lane.is_empty() and lane.back() == id:
			return true
	return false


func move(ns: NodeState, id: String, destination: int) -> OperationResult:
	if not accessible(ns, id):
		return OperationResult.fail("只能移动可接触的顶层牌")
	var card: Dictionary = ns.scene_cards[id]
	if card["kind"] not in ["cover", "container"]:
		return OperationResult.fail("该对象不可移动")
	if destination < 0 or destination >= ns.card_lanes.size():
		return OperationResult.fail("落点不存在")
	var target: Array = ns.card_lanes[destination]
	if target.has(id):
		return OperationResult.fail("已在该位置")
	if not target.is_empty():
		var support: Dictionary = ns.scene_cards[target.back()]
		if support["kind"] not in ["cover", "container"] or target.size() >= 2:
			return OperationResult.fail("落点不能承接或已满")
	for lane in ns.card_lanes:
		if not lane.is_empty() and lane.back() == id:
			lane.pop_back()
			break
	target.append(id)
	return OperationResult.ok()
