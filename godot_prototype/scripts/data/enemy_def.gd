class_name EnemyDef
extends Resource
## 敌人定义。敌人与玩家使用同一套物品与公共战斗机制。

@export var template_id: StringName = &""
@export var display_name: String = ""
@export var max_hp: float = 48.0
@export var equipment: Array[GrantDef] = []
@export var skills: Array[GrantDef] = []
## 可掉落条目：默认等于 equipment + skills 中的合法条目；留空则由二者推导。
@export var drop_entries: Array[GrantDef] = []
## 是否为主线目标
@export var is_main_target: bool = false

func resolved_drop_entries() -> Array[GrantDef]:
	if not drop_entries.is_empty():
		return drop_entries
	var out: Array[GrantDef] = []
	for g in equipment:
		out.append(g)
	for g in skills:
		out.append(g)
	return out
