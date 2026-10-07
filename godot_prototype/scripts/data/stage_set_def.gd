class_name StageSetDef
extends Resource
## 阶段对手集合：固定配置模板 + 随机追加组件池。
## 九种配置 = 3 模板 × 3 追加组件。生成一次后固定，重试不改变。

@export var stage_id: StringName = &""
@export var display_name: String = ""
@export var max_hp: float = 100.0
@export var templates: Array[StageTemplateDef] = []
@export var extra_pool: Array[GrantDef] = []
## 阶段对手不附加职业、血统、独立技能
@export var grants_traits: bool = false
@export var grants_skills: bool = false
