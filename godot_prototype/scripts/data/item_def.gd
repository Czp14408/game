class_name ItemDef
extends Resource
## 物品定义（只读定义，不含玩家实例状态）。
## 依据：游戏可玩原型技术方案.md 第 5 节；数值依据 游戏最小战斗与经济方案.md 第 3 节。

const CAT_WEAPON := &"weapon"
const CAT_SHIELD := &"shield"
const CAT_HEAL := &"heal"
const CAT_BURN := &"burn"
const CAT_POISON := &"poison"
const CAT_HASTE := &"haste"
const CAT_SLOW := &"slow"
const CAT_FREEZE := &"freeze"
const CAT_CONSUMABLE := &"consumable"
const CAT_MATERIAL := &"material"

## 自身被动：当使用武器时，充能此物品 1 秒
const PASSIVE_CHARGE_ON_WEAPON_USE := &"charge_on_weapon_use"

@export var definition_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = CAT_WEAPON
@export var tags: Array[StringName] = []
## 占格：小 1 / 中 2 / 大 3
@export var size: int = 1
## 冷却毫秒
@export var cooldown_ms: int = 0
## 四档品质数值 [青铜, 白银, 黄金, 钻石]
@export var tier_values: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0])
@export var effects: Array[EffectDef] = []
@export var self_passive: StringName = &""
## 是否可以放入战斗栏
@export var equippable: bool = true
## 恢复品：战斗外使用恢复量
@export var out_of_combat_heal: float = 0.0
## 标准购买价覆盖（留空则按占格与品质查价目表）
@export var fixed_base_price: int = -1

func value_at(quality: int) -> float:
	if tier_values.is_empty():
		return 0.0
	return tier_values[clampi(quality, 0, tier_values.size() - 1)]

func is_weapon() -> bool:
	return category == CAT_WEAPON

func is_active() -> bool:
	return equippable and not effects.is_empty()

func primary_effect() -> EffectDef:
	return effects[0] if not effects.is_empty() else null
