class_name ConnectionDef
extends Resource
## 节点连接。守路条件直接作用于指定连接。

@export var node_a: String = ""
@export var node_b: String = ""
## 守路敌人模板 id；留空表示无守路条件
@export var guard_enemy_id: StringName = &""
## 守路条件发现后是否显示原因（首版为 true）
@export var reveal_reason: bool = true

func connects(p_a: String, p_b: String) -> bool:
	return (node_a == p_a and node_b == p_b) or (node_a == p_b and node_b == p_a)

func other(p_node: String) -> String:
	return node_b if node_a == p_node else node_a
