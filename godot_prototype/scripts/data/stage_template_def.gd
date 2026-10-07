class_name StageTemplateDef
extends Resource
## 阶段对手的固定配置模板。

@export var template_id: StringName = &""
@export var display_name: String = ""
@export var equipment: Array[GrantDef] = []

func total_size(catalog: ContentCatalog) -> int:
	var total := 0
	for g in equipment:
		var def := catalog.item(g.definition_id)
		if def != null:
			total += def.size
	return total
