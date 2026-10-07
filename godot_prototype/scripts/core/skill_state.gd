class_name SkillState
extends RefCounted
## 已学技能状态。技能无数量上限，全部生效；同名效果不重复叠加。

var skill_id: StringName = &""
var quality: int = 0
## 本次试炼成长（替换与合成时保留）
var trial_growth: float = 0.0


static func make(p_id: StringName, p_quality: int = 0) -> SkillState:
	var s := SkillState.new()
	s.skill_id = p_id
	s.quality = p_quality
	return s
