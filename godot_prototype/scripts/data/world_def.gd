class_name WorldDef
extends Resource
## 任务世界定义：节点、连接、入口、主线位置、任务。
## 依据：游戏单局推演.md 第 3 节 18 节点样本连接。

@export var world_id: StringName = &""
@export var display_name: String = ""
@export var entry_node_id: String = "01"
@export var nodes: Array[NodeDef] = []
@export var connections: Array[ConnectionDef] = []
@export var quests: Array[QuestDef] = []

func node_by_id(p_id: String) -> NodeDef:
	for n in nodes:
		if n.node_id == p_id:
			return n
	return null

func neighbors(p_id: String) -> Array[String]:
	var out: Array[String] = []
	for c in connections:
		if c.node_a == p_id:
			out.append(c.node_b)
		elif c.node_b == p_id:
			out.append(c.node_a)
	return out

func connection_between(p_a: String, p_b: String) -> ConnectionDef:
	for c in connections:
		if c.connects(p_a, p_b):
			return c
	return null

func quest_by_id(p_id: StringName) -> QuestDef:
	for q in quests:
		if q.quest_id == p_id:
			return q
	return null
