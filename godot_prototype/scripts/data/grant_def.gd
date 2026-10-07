class_name GrantDef
extends Resource
## 通用“授予一项内容”的描述：物品 + 品质（+ 敌人额外强化值）或技能 + 品质。
## 用于敌人配置、阶段对手模板、奖励与掉落条目。

@export var definition_id: StringName = &""
@export var quality: int = 0
## 仅敌人配置使用：额外伤害强化（不参与掉落复制）
@export var extra_value: float = 0.0
@export var is_skill: bool = false

static func item(p_id: StringName, p_quality: int = 0, p_extra: float = 0.0) -> GrantDef:
	var g := GrantDef.new()
	g.definition_id = p_id
	g.quality = p_quality
	g.extra_value = p_extra
	return g

static func skill(p_id: StringName, p_quality: int = 0) -> GrantDef:
	var g := GrantDef.new()
	g.definition_id = p_id
	g.quality = p_quality
	g.is_skill = true
	return g
