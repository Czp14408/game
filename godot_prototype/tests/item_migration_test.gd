extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:
		failed+=1
		printerr(label)
func _initialize() -> void:
	var catalog := ContentCatalog.load_default()
	check(catalog.items_from_excel,"物品唯一来源为 Excel")
	check(catalog.items.size()==catalog.generated_item_ids.size(),"无旧目录混合加载")
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_items_baseline.json"))
	for record in baseline:
		var item := catalog.item(StringName(record["id"]))
		check(item!=null,"迁移 ID 存在："+record["id"])
		if item==null:continue
		for field in ["category","size","cooldown_ms","self_passive","equippable","out_of_combat_heal","fixed_base_price"]:
			check(item.get(field)==record[field],"%s/%s 保持一致" % [record["id"],field])
		var tags := PackedStringArray()
		for value in item.tags:tags.append(String(value))
		check(item.display_name==record["name"] and Array(item.tier_values)==record["values"] and tags==PackedStringArray(record["tags"]),"名称、TAG 与四品质数值保持一致")
		check(item.effects.size()==record["effects"].size(),"效果数量保持一致")
		for index in item.effects.size():
			var effect := item.effects[index]
			var old: Dictionary = record["effects"][index]
			check(String(effect.effect_type)==old["type"] and String(effect.target_rule)==old["target"] and String(effect.emits_event)==old["event"],"动作、目标、事件保持一致")
			for quality in range(4):check(effect.value_at(quality,item.value_at(quality))==record["values"][quality],"四品质效果保持一致")
		check(not FileAccess.file_exists("res://data/items/%s.tres" % record["id"]),"旧定义已退出活动目录")
	check(not FileAccess.get_file_as_string("res://tools/build_content.gd").contains("_build_items"),"旧生成器关闭物品写入")
	for shop in catalog.shops.values():
		check(shop.item_candidates.is_empty() and shop.equipment_pool.is_empty(),"商店物品候选不再保留两套来源")
	print("旧物品迁移验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
