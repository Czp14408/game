class_name PriceTable
extends RefCounted
## 标准价目表与出售回收。
## 依据：游戏最小战斗与经济方案.md 第 6 节。标准价全为偶数，回收严格减半，不需取整。

const QUALITY_NAMES: PackedStringArray = ["青铜", "白银", "黄金", "钻石"]

## 占格 1/2/3 分别对应小型/中型/大型装备
static var SIZE_PRICES := {
	1: PackedInt32Array([6, 10, 16, 24]),
	2: PackedInt32Array([10, 16, 26, 40]),
	3: PackedInt32Array([14, 22, 36, 56]),
}
const SKILL_PRICES: PackedInt32Array = [12, 20, 32, 48]
const RECOVERY_DRAUGHT_PRICE := 6
const MATERIAL_VALUATION := 8


static func quality_name(q: int) -> String:
	return QUALITY_NAMES[clampi(q, 0, QUALITY_NAMES.size() - 1)]


static func item_base_price(def: ItemDef, quality: int) -> int:
	if def == null:
		return 0
	if def.fixed_base_price >= 0:
		return def.fixed_base_price
	var row: PackedInt32Array = SIZE_PRICES.get(clampi(def.size, 1, 3), PackedInt32Array([0, 0, 0, 0]))
	return row[clampi(quality, 0, row.size() - 1)]


static func item_sell_price(def: ItemDef, quality: int) -> int:
	return item_base_price(def, quality) / 2


static func skill_base_price(quality: int) -> int:
	return SKILL_PRICES[clampi(quality, 0, SKILL_PRICES.size() - 1)]


## 技能不能出售
static func skill_sell_price(_quality: int) -> int:
	return 0


static func material_sell_price() -> int:
	return MATERIAL_VALUATION / 2


## 付费合成与出售不能赚钱：重复件合成后按新档位计价，不高于两件原价之和
static func synthesis_is_profitable(def: ItemDef, quality: int) -> bool:
	if quality >= 3:
		return false
	return item_sell_price(def, quality + 1) > item_sell_price(def, quality) * 2
