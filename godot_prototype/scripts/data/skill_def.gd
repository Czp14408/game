class_name SkillDef
extends Resource
## 独立被动技能定义。技能全部为被动，无主动技能。
## 依据：游戏最小战斗与经济方案.md 第 4 节。

const TRIGGER_USE_SHIELD := &"use_shield"       # 越战越勇
const TRIGGER_APPLY_BURN := &"apply_burn"       # 火势护体
const TRIGGER_HEAL := &"heal"                   # 回春护体

@export var definition_id: StringName = &""
@export var display_name: String = ""
## 监听事件类型
@export var trigger_event: StringName = &""
## 触发后的效果：weapon_damage_growth / shield_gain
@export var effect_type: StringName = &""
@export var effect_amount: float = 0.0
## 四档数值 [青铜, 白银, 黄金, 钻石]
@export var tier_values: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0])
@export var description: String = ""

func value_at(quality: int) -> float:
	if effect_amount > 0.0:
		return effect_amount
	if tier_values.is_empty():
		return 0.0
	return tier_values[clampi(quality, 0, tier_values.size() - 1)]
