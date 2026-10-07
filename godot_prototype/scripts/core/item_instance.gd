class_name ItemInstance
extends RefCounted
## 物品实例。同名装备的实例必须有不同 ID；战斗运行数据另建，不写回共享定义。

const LOC_NONE := &"none"
const LOC_BATTLE := &"battle_bar"
const LOC_INVENTORY := &"inventory"

var instance_id: String = ""
var definition_id: StringName = &""
var quality: int = 0
## 本次试炼成长（跨战斗、跨节点保留，试炼结束清除；合成时两件加总继承）
var trial_growth: float = 0.0
var location: StringName = LOC_INVENTORY
## 来源节点（用于日志与拾取追溯）
var origin_node: String = ""


static func make(p_def_id: StringName, p_quality: int = 0, p_seq: int = 0) -> ItemInstance:
	var it := ItemInstance.new()
	it.instance_id = "it_%s_q%d_%d" % [p_def_id, p_quality, p_seq]
	it.definition_id = p_def_id
	it.quality = p_quality
	return it


func value_with_growth(catalog: ContentCatalog) -> float:
	var def := catalog.item(definition_id)
	if def == null:
		return 0.0
	return def.value_at(quality) + trial_growth


func display_name(catalog: ContentCatalog) -> String:
	var def := catalog.item(definition_id)
	if def == null:
		return String(definition_id)
	return "%s（%s）" % [def.display_name, PriceTable.quality_name(quality)]


func size(catalog: ContentCatalog) -> int:
	var def := catalog.item(definition_id)
	return def.size if def != null else 0
