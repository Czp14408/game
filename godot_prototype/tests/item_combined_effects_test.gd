extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr(label)

func _initialize() -> void:
	var catalog := ContentCatalog.load_default()
	for id in ["combined_small", "combined_medium"]:
		var definition := load("res://tests/fixtures/%s.tres" % id) as ItemDef
		check(definition != null, "Excel 编译生成的组合资源可读取")
		catalog.items[definition.definition_id] = definition
		for quality in range(4):
			var player := CombatEngine.build_actor(catalog, {"max_hp":1000, "hp":1, "items":[{"definition_id":definition.definition_id,"quality":quality}]})
			var enemy := CombatEngine.build_actor(catalog, {"side":1,"max_hp":1000,"hp":1000})
			var engine := CombatEngine.new()
			engine.catalog = catalog
			engine.rng = RandomService.create(1)
			engine.begin(player, enemy, "combined", "combined")
			for step in range(29): engine.step()
			check(player.items[0].uses == 0, "所有组合效果等待同一自然冷却")
			engine.step()
			var count := definition.multicast_at(quality)
			check(player.items[0].uses == count, "使用次数不乘以属性数量")
			check(enemy.hp == 1000-(8+quality)*count, "独立攻击数值按品质与多重次数结算")
			check(player.shield == (5+quality)*count, "独立护盾数值结算")
			check(enemy.total_poison() == definition.value_at(quality)*count, "主属性中毒数值不被附加属性覆盖")
			if id == "combined_medium":
				check(player.hp == 1+(2+quality)*count, "附加治疗读取自己的品质数值")
				check(enemy.total_burn() == (4+quality)*count, "附加灼烧读取自己的品质数值")
			var uses := 0
			for event in engine.get("_result").events:
				if event["type"] == String(BattleEvent.TYPE_USE_ITEM): uses += 1
			check(uses == count, "每次使用只有一个使用物品事件")
			check(player.items[0].cooldown_remaining_ms == 3000, "多个属性共用一次 CD 重置")
			var card := ItemCard.new()
			card.size = Vector2(56*definition.size,112)
			card.configure({"definition":definition,"quality":quality,"battle_state":player.items[0]})
			check(card.stat_values().size() == definition.effects.size(), "卡面展示全部独立属性")
			for stat in card.stat_values():
				if stat["kind"] == "attack": check(stat["value"] == 8+quality, "卡面显示单次攻击，非多重总和")
				if stat["kind"] == "shield": check(stat["value"] == 5+quality, "卡面显示单次护盾")
			player.items[0].battle_growth = 7
			check(card.effect_value(definition.effects[1]) == 8+quality, "主属性变化不会串改附加属性")
			check(card.description().contains("连续使用 %d 次" % count), "悬停同时包含多重次数及各效果")
			card.free()
	check(catalog.validate().is_empty(), "组合资源通过完整内容参数检查")
	var small: ItemDef = catalog.items[&"combined_small"]
	var saved := small.effects[1].tier_values
	small.effects[1].tier_values = PackedFloat64Array([1, 2])
	check(not catalog.validate().is_empty(), "独立属性缺失品质数值拒绝加载")
	small.effects[1].tier_values = saved
	small.effects.append(small.effects[1])
	check(not catalog.validate().is_empty(), "小卡超出属性数量上限拒绝加载")
	small.effects.pop_back()
	print("组合效果验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
