class_name EncounterState
extends RefCounted
## 遭遇状态：未击败/已击败、奖励结算标记、待拾取掉落。
## 失败遭遇恢复到战前状态，战斗内临时效果清除。

var encounter_key: String = ""        # node_id>template#index
var node_id: String = ""
var enemy_template_id: StringName = &""
var defeated: bool = false
var reward_claimed: bool = false
var result_submitted: bool = false
var battle_id: String = ""
var is_guard: bool = false
## 取消挑战后屏蔽该敌人的自动弹窗；离开接触区域后解除
var auto_prompt_suppressed: bool = false
## 待拾取实物（货币与胜负已先结算；容量不足时保留为待拾取掉落）
var pending_drops: Array = []          # Array[ItemInstance]
## 待决策的技能掉落：{"skill_id": StringName, "quality": int}
var pending_skill: Dictionary = {}
var last_result: BattleResult = null
