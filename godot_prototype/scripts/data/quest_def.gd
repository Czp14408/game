class_name QuestDef
extends Resource
## 任务定义。主线完成自动结算；支线领取方式由任务明确。
## 依据：游戏核心规则定稿.md 第 1、6 节；一阶段需求 首版支线目标追认。

const OBJECTIVE_KILL_ENEMY := &"kill_enemy"
const OBJECTIVE_CHALLENGE := &"challenge"

const CLAIM_AUTO := &"auto_on_complete"
const CLAIM_NPC := &"npc_claim"

@export var quest_id: StringName = &""
@export var display_name: String = ""
@export var is_main: bool = false
@export var objective_type: StringName = OBJECTIVE_KILL_ENEMY
## 目标敌人模板 id
@export var target_enemy_id: StringName = &""
## 目标所在节点；留空表示任意节点
@export var target_node_id: String = ""
@export var reward_money: int = 0
## 奖励账本 ID，用于防重复领取
@export var reward_id: StringName = &""
@export var claim_mode: StringName = CLAIM_AUTO
## 领奖 NPC 所在节点（claim_mode = npc_claim）
@export var claim_node_id: String = ""
## 是否追认接取前已完成的目标（首版两项支线为 true）
@export var retroactive: bool = false
@export var description: String = ""
