class_name BattleItemState
extends RefCounted
## 战斗中的单件物品运行状态。绝不写回共享定义，避免一件装备成长影响所有同名装备。

var instance_id: String = ""
var definition_id: StringName = &""
var display_name: String = ""
var category: StringName = &""
var size: int = 1
var quality: int = 0
var effects: Array[EffectDef] = []
var self_passive: StringName = &""
var base_cd_ms: int = 0
## 定义数值 + 敌人额外强化 + 物品本次试炼成长
var base_value: float = 0.0
## 本场战斗内的数值成长（战后清除）
var battle_growth: float = 0.0

## 本场冷却与控制剩余时间（毫秒）
var cooldown_remaining_ms: int = 0
var freeze_ms: int = 0
var slow_ms: int = 0
var haste_ms: int = 0

var uses: int = 0
## 本步锁定释放时的效果值快照
var locked_value: float = 0.0
var locked_this_step: bool = false

## --- 统计归属（本场）---
var damage_attack: float = 0.0
var damage_burn: float = 0.0
var damage_poison: float = 0.0
var shield_gained: float = 0.0
var heal_computed: float = 0.0
var heal_actual: float = 0.0


func is_weapon() -> bool:
	return category == ItemDef.CAT_WEAPON


func is_frozen() -> bool:
	return freeze_ms > 0


func is_ready() -> bool:
	return cooldown_remaining_ms <= 0


## 加速提高自然冷却推进速度，减速降低；二者同时存在时按正常速度
func natural_advance_ms(step_ms: int) -> int:
	if haste_ms > 0 and slow_ms > 0:
		return step_ms
	if haste_ms > 0:
		return step_ms * 2
	if slow_ms > 0:
		return step_ms / 2
	return step_ms


func primary_effect() -> EffectDef:
	return effects[0] if not effects.is_empty() else null


func stats_summary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": String(definition_id),
		"display_name": display_name,
		"quality": quality,
		"uses": uses,
		"damage_attack": damage_attack,
		"damage_burn": damage_burn,
		"damage_poison": damage_poison,
		"damage_total": damage_attack + damage_burn + damage_poison,
		"shield_gained": shield_gained,
		"heal_computed": heal_computed,
		"heal_actual": heal_actual,
	}
