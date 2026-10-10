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
	for kind in ["weapon", "shield", "heal", "burn", "poison"]:
		for count in [2, 10]:
			var definition := catalog.item(&"poison_vial").duplicate() as ItemDef
			definition.definition_id = &"multicast_test"
			definition.category = StringName(kind)
			definition.cooldown_ms = 300
			definition.tier_values = PackedFloat64Array([3, 3, 3, 3])
			definition.tier_multicast = PackedInt32Array([count, count, count, count])
			catalog.items[definition.definition_id] = definition
			var player := CombatEngine.build_actor(catalog, {"max_hp": 1000, "hp": 1, "items": [{"definition_id": definition.definition_id}]})
			var enemy := CombatEngine.build_actor(catalog, {"side": 1, "max_hp": 1000, "hp": 1000})
			var engine := CombatEngine.new()
			engine.catalog = catalog
			engine.rng = RandomService.create(1)
			engine.begin(player, enemy, "multi", "multi")
			engine.step()
			engine.step()
			check(player.items[0].uses == 0, "%s ×%d CD 到期前不释放" % [kind, count])
			engine.step()
			check(player.items[0].uses == count, "释放统计按每次使用计数")
			check(player.items[0].cooldown_remaining_ms == 300, "一轮多重释放只重置一次 CD")
			var use_events := 0
			for event in engine.get("_result").events:
				if event["type"] == String(BattleEvent.TYPE_USE_ITEM): use_events += 1
			check(use_events == count, "所有基础物品逐次产生使用物品事件")
			match kind:
				"weapon":
					check(enemy.hp == 1000 - 3 * count, "攻击逐次结算")
					var uses := 0
					for event in engine.get("_result").events:
						if event["type"] == String(BattleEvent.TYPE_USE_WEAPON): uses += 1
					check(uses == count, "每次释放分别产生使用武器事件")
				"shield": check(player.shield == 3 * count, "护盾逐次叠加")
				"heal": check(player.hp == 1 + 3 * count and player.items[0].heal_computed == 3 * count, "治疗逐次结算及统计")
				"burn": check(enemy.total_burn() == 3 * count, "灼烧逐次施加")
				"poison": check(enemy.total_poison() == 3 * count, "中毒逐次施加")
			engine.step()
			check(player.items[0].uses == count and player.items[0].cooldown_remaining_ms == 200, "下一步继续自然冷却，无残余额外使用")
	# A repeated use must trigger charge and lifesteal per release, not once per burst.
	var weapon: ItemDef = catalog.items[&"multicast_test"]
	weapon.category = ItemDef.CAT_WEAPON
	weapon.tier_multicast = PackedInt32Array([2, 2, 2, 2])
	var charged := weapon.duplicate() as ItemDef
	charged.definition_id = &"charged_test"
	charged.category = ItemDef.CAT_SHIELD
	charged.cooldown_ms = 4000
	charged.self_passive = ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE
	charged.tier_multicast = PackedInt32Array([1, 1, 1, 1])
	catalog.items[charged.definition_id] = charged
	var player := CombatEngine.build_actor(catalog, {"max_hp": 1000, "hp": 1, "items": [{"definition_id": weapon.definition_id}, {"definition_id": charged.definition_id}]})
	var enemy := CombatEngine.build_actor(catalog, {"side": 1, "max_hp": 1000, "hp": 1000})
	var engine := CombatEngine.new()
	engine.catalog = catalog
	engine.rng = RandomService.create(1)
	engine.begin(player, enemy, "chain", "chain")
	player.heal_on_weapon_use = 2
	for step in range(3): engine.step()
	check(player.items[1].cooldown_remaining_ms == 1700, "两次武器使用分别充能被动物品")
	check(player.items[1].charge_visual_seq == 2, "每次真实充能记录视觉触发，供共用动效读取")
	check(player.hp == 5, "两次武器使用分别触发吸血")
	engine.begin(player, enemy, "freeze", "freeze")
	player.items[0].freeze_ms = 400
	for step in range(6): engine.step()
	check(player.items[0].uses == 0, "冻结结束后才推进多重释放物品的自然冷却")
	engine.step()
	check(player.items[0].uses == 2, "冻结不会取消多重释放配置")
	weapon.category = ItemDef.CAT_HEAL
	player = CombatEngine.build_actor(catalog, {"max_hp": 100, "hp": 99, "items": [{"definition_id": weapon.definition_id}]})
	enemy = CombatEngine.build_actor(catalog, {"side": 1, "max_hp": 1000, "hp": 1000})
	engine.begin(player, enemy, "heal", "heal")
	for step in range(3): engine.step()
	var heals: Array = []
	for event in engine.get("_result").events:
		if event["type"] == String(BattleEvent.TYPE_HEAL) and event.has("target_side"): heals.append(event["actual"])
	check(heals == [1.0, 0.0], "两次治疗分别记录实际回复，包括满血的第二次")
	var def := catalog.item(&"poison_vial").duplicate() as ItemDef
	def.tier_multicast = PackedInt32Array([1, 2, 5, 10])
	for quality in range(4):
		var card := ItemCard.new()
		card.size = Vector2(56, 112)
		card.configure({"definition": def, "quality": quality})
		var badge := card.stat_layer.get_node_or_null("Multicast")
		check((badge == null) == (quality == 0), "×1 隐藏，其余品质显示多重释放吊牌")
		if badge != null:
			check(badge.position.x >= 0 and badge.position.x + badge.size.x <= card.size.x, "×10 吊牌不侵占邻格")
			check(badge.position.y >= card.stat_layer.get_child(0).position.y + card.stat_layer.get_child(0).size.y, "释放次数与属性数值不重叠")
			check(card.description().contains("连续使用 %d 次" % def.multicast_at(quality)), "悬停说明自动生成释放次数")
		card.free()
	check(catalog.item(&"poison_vial").multicast_at(0) == 1, "测试不改变正式砒霜定义")
	print("多重释放验证：通过 %d，失败 %d" % [passed, failed])
	quit(1 if failed else 0)
