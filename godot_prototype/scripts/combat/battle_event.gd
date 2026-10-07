class_name BattleEvent
extends RefCounted
## 公共战斗事件。同一 event_id 不得重复处理。

const TYPE_USE_ITEM := &"use_item"           # 任意主动物品实际释放
const TYPE_USE_WEAPON := &"use_weapon"
const TYPE_USE_SHIELD := &"use_shield"
const TYPE_HEAL := &"heal"
const TYPE_APPLY_BURN := &"apply_burn"
const TYPE_APPLY_POISON := &"apply_poison"
const TYPE_DAMAGE := &"damage"
const TYPE_SHIELD_GAIN := &"shield_gain"
const TYPE_SKILL_TRIGGER := &"skill_trigger"
const TYPE_STORM := &"storm"
const TYPE_DEATH := &"death"

var event_id: String = ""
var step: int = 0
var type: StringName = &""
var source_instance_id: String = ""
var source_side: int = CombatActor.SIDE_PLAYER
var target_side: int = CombatActor.SIDE_ENEMY
var computed: float = 0.0
var actual: float = 0.0
var detail: Dictionary = {}
var processed: bool = false


func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"step": step,
		"type": String(type),
		"source": source_instance_id,
		"source_side": source_side,
		"target_side": target_side,
		"computed": computed,
		"actual": actual,
		"detail": detail,
	}
