class_name NodeDef
extends Resource
## 世界节点定义。节点是小地图的配置来源，不等于玩家已探索状态。

const LAYOUT_TOWN := &"town"
const LAYOUT_ROAD := &"road"
const LAYOUT_CAMP := &"camp"

const NPC_SHOP := &"shop"                        # 商店由 shop_ids 描述
const NPC_INTEL_AREA := &"intel_area"            # 揭示土匪活动区域
const NPC_INTEL_TARGET := &"intel_target"        # 揭示头子准确节点与战斗风格
const NPC_QUEST_CHALLENGE := &"quest_challenge"  # 武馆挑战支线
const NPC_QUEST_SIDE := &"quest_side"            # 击杀路匪支线委托（含领奖）

@export var node_id: String = ""
@export var display_name: String = ""
@export var layout: StringName = LAYOUT_TOWN
@export var shop_ids: Array[StringName] = []
@export var enemies: Array[StringName] = []
@export var npc_services: Array[StringName] = []
@export var quest_ids: Array[StringName] = []
## 容器：开一次生成一次
@export var has_container: bool = false
## 容器内容表：material_small（材料）/ supply_small（恢复品或材料）
@export var container_table: StringName = &""
@export var is_main_target: bool = false
