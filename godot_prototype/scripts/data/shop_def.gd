class_name ShopDef
extends Resource
## 商店定义。商品数量、刷新费、品质概率为第一阶段测试值。
## 依据：游戏最小战斗与经济方案.md 第 6 节；候选池默认见 技术方案 第 12 节。

@export var shop_id: StringName = &""
@export var display_name: String = ""
## 抽取模式：candidates = 从候选池等概率；mixed = 先抽类别再抽定义
const MODE_CANDIDATES := &"candidates"
const MODE_MIXED := &"mixed"
@export var mode: StringName = MODE_CANDIDATES

## 候选池：物品 definition_id 列表（mode = candidates）
@export var item_candidates: Array[StringName] = []
## 技能候选池
@export var skill_candidates: Array[StringName] = []
## mode = mixed 时：装备/技能类别权重
@export var equipment_weight: float = 0.8
@export var skill_weight: float = 0.2
## mode = mixed 时：装备池与技能池
@export var equipment_pool: Array[StringName] = []

@export var item_count: int = 4
@export var refresh_cost: int = 3
## 品质概率 [青铜, 白银, 黄金, 钻石]，和必须为 1
@export var quality_weights: PackedFloat64Array = PackedFloat64Array([0.85, 0.15, 0.0, 0.0])
## 该店是否出售恢复品（恢复品只在补给类店铺池）
@export var sells_consumable: bool = false

func pool_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(equipment_pool)
	out.append_array(item_candidates)
	out.append_array(skill_candidates)
	return out
