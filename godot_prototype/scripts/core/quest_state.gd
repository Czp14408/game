class_name QuestState
extends RefCounted
## 任务状态。每项奖励最多领取一次（由 reward_id 防重复）。

const STATUS_LOCKED := &"locked"       # 尚未接取
const STATUS_ACCEPTED := &"accepted"   # 进行中
const STATUS_COMPLETED := &"completed" # 目标达成、待领奖
const STATUS_CLAIMED := &"claimed"     # 已领奖

var quest_id: StringName = &""
var status: StringName = STATUS_LOCKED
var progress: int = 0


func is_done() -> bool:
	return status == STATUS_COMPLETED or status == STATUS_CLAIMED


func is_claimed() -> bool:
	return status == STATUS_CLAIMED
