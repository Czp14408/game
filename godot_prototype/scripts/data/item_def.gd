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
## Excel 内容的完整物品图片路径；允许带背景。展示接入独立于内容加载。
@export var icon_path: String = ""
@export var category: StringName = CAT_WEAPON
@export var tags: Array[StringName] = []
## Localized TAG labels exported from the Excel dictionary.
@export var display_tags: PackedStringArray = []
## 占格：小 1 / 中 2 / 大 3
@export var size: int = 1
## 冷却毫秒
@export var cooldown_ms: int = 0
## 四档品质数值 [青铜, 白银, 黄金, 钻石]
@export var tier_values: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0])
## Per-quality natural cooldown burst count; each release is a separate use.
@export var tier_multicast: PackedInt32Array = PackedInt32Array([1, 1, 1, 1])
@export var effects: Array[EffectDef] = []
## 每次使用先提升己方所有武器，包含自身，仅本场有效；空数组表示无成长。
@export var tier_weapon_growth: PackedFloat64Array = []
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

func multicast_at(quality: int) -> int:
	if tier_multicast.is_empty():
		return 1
	return clampi(tier_multicast[clampi(quality, 0, tier_multicast.size()-1)], 1, 10)

func weapon_growth_at(quality: int) -> float:
	return 0.0 if tier_weapon_growth.is_empty() else tier_weapon_growth[clampi(quality, 0, tier_weapon_growth.size()-1)]
