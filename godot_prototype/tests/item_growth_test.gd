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
	var blade := load("res://tests/fixtures/growth_blade.tres") as ItemDef
	catalog.items[blade.definition_id] = blade
	check(catalog.validate().is_empty(), "成长资源通过内容检查")
	for count in [1,2,10]:
		for quality in range(4):
			blade.tier_multicast = PackedInt32Array([count,count,count,count])
			var player := CombatEngine.build_actor(catalog, {"max_hp":100000,"items":[{"definition_id":"growth_blade","quality":quality}]})
			var enemy := CombatEngine.build_actor(catalog, {"side":1,"max_hp":100000})
			var engine := CombatEngine.new()
			engine.catalog = catalog
			engine.rng = RandomService.create(1)
			engine.begin(player,enemy,"growth","growth")
			for step in range(19): engine.step()
			check(player.items[0].battle_growth == 0, "就绪前不成长")
			engine.step()
			var growth := blade.weapon_growth_at(quality)
			var base := blade.value_at(quality)
			var expected: float = base*count + growth*count*(count+1)/2.0
			check(player.items[0].damage_attack == expected, "逐次先成长再攻击")
			check(player.items[0].battle_growth == growth*count, "每次使用都成长")
			check(player.items[0].uses == count, "多重独立使用次数")
			check(player.items[0].cooldown_remaining_ms == 2000, "多重只重置一次 CD")
			var card := ItemCard.new()
			card.configure({"definition":blade,"quality":quality,"battle_state":player.items[0]})
			check(card.stat_values().size() == 1, "成长不增加卡面属性徽章")
			check(card.final_value() == base+growth*count, "卡面仅显示成长后最终攻击")
			check(card.description().contains("包含自身") and card.description().contains("本场战斗有效"), "悬停解释成长范围与期限")
			card.free()
			check(blade.value_at(quality) == base, "共享定义不被成长写回")
			engine.begin(player,enemy,"next","next")
			check(player.items[0].battle_growth == 0, "下场战斗清除成长")
	# 同轮两把成长武器先汇总成长，调换装备顺序结果不变；未就绪的武器也受益。
	blade.tier_multicast = PackedInt32Array([2,2,2,2])
	for reverse in [false,true]:
		var grants := [{"definition_id":"growth_blade","quality":0},{"definition_id":"growth_blade","quality":1},{"definition_id":"growth_blade","quality":2}]
		if reverse: grants.reverse()
		var player := CombatEngine.build_actor(catalog, {"max_hp":100000,"items":grants})
		var enemy := CombatEngine.build_actor(catalog, {"side":1,"max_hp":100000,"items":[{"definition_id":"growth_blade"}]})
		var engine := CombatEngine.new()
		engine.catalog = catalog
		engine.rng = RandomService.create(1)
		engine.begin(player,enemy,"same","same")
		for item in player.items:
			if item.quality == 2: item.freeze_ms = 3000
		for step in range(20): engine.step()
		for item in player.items:
			check(item.battle_growth == 24, "己方所有武器包含冻结者受益")
			if item.quality < 2:
				check(item.damage_attack == blade.value_at(item.quality)*2+36, "同轮成长不受装备顺序影响")
			else: check(item.uses == 0, "冻结者不触发自身成长和攻击")
		check(enemy.items[0].battle_growth == 10, "成长不影响敌方武器")
	print("成长攻击验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
