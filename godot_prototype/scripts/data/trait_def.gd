class_name TraitDef
extends Resource
## 职业 / 血统定义。无品质，提供被动规则与基础属性修正。
## 依据：游戏最小战斗与经济方案.md 第 4 节。

const KIND_PROFESSION := &"profession"
const KIND_BLOODLINE := &"bloodline"

const EFFECT_WEAPON_DAMAGE_FLAT := &"weapon_damage_flat"
const EFFECT_HEAL_COMPUTED_FLAT := &"heal_computed_flat"
const EFFECT_MAX_HP_FLAT := &"max_hp_flat"
const EFFECT_HEAL_ON_WEAPON_USE := &"heal_on_weapon_use"

@export var trait_id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = KIND_PROFESSION
@export var effect_type: StringName = &""
@export var effect_amount: float = 0.0
@export var description: String = ""
