class_name EffectDef
extends Resource
## 效果定义：只描述“已实现的效果类型”，不允许可执行表达式。
## 依据：游戏可玩原型技术方案.md 第 5 节。

const TYPE_ATTACK := &"attack"
const TYPE_SHIELD := &"shield"
const TYPE_HEAL := &"heal"
const TYPE_BURN := &"burn"
const TYPE_POISON := &"poison"
const TYPE_HASTE := &"haste"
const TYPE_SLOW := &"slow"
const TYPE_FREEZE := &"freeze"

## enemy / self / own_other_active_item / enemy_active_item
const TARGET_ENEMY := &"enemy"
const TARGET_SELF := &"self"
const TARGET_OWN_OTHER_ITEM := &"own_other_active_item"
const TARGET_ENEMY_ITEM := &"enemy_active_item"

@export var effect_type: StringName = TYPE_ATTACK
@export var target_rule: StringName = TARGET_ENEMY
## 取值来源：tier = 使用四档品质数值表；fixed = 使用 fixed_value
@export var value_source: StringName = &"tier"
@export var fixed_value: float = 0.0
## 释放时抛出的公共事件；留空表示不抛出
## use_weapon / use_shield / heal / apply_burn / apply_poison（由物品类别补充）
@export var emits_event: StringName = &""


static func make(p_type: StringName, p_target: StringName, p_event: StringName = &"") -> EffectDef:
	var e := EffectDef.new()
	e.effect_type = p_type
	e.target_rule = p_target
	e.emits_event = p_event
	return e
