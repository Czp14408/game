extends SceneTree
## Integration contract for generated content, natural stock, and combat timing.
var failed := 0
var passed := 0


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("失败：" + label)


func _initialize() -> void:
	var catalog := ContentCatalog.load_default()
	check(catalog.validate().is_empty(), "内容目录校验")
	var item := catalog.item(&"poison_vial")
	check(item != null, "Excel 物品已加载")
	if item == null:
		quit(1)
		return
	check(item.cooldown_ms == 3000, "冷却 3000 毫秒")
	check(item.tier_values == PackedFloat64Array([3, 6, 9, 12]), "四档中毒数值")
	check(ResourceLoader.exists(item.icon_path), "完整背景图片可加载")
	for quality in range(4):
		var player := CombatEngine.build_actor(catalog, {"items": [{"definition_id": &"poison_vial", "quality": quality}], "max_hp": 1000.0, "hp": 1000.0})
		var enemy := CombatEngine.build_actor(catalog, {"side": 1, "max_hp": 1000.0, "hp": 1000.0})
		var engine := CombatEngine.new()
		engine.catalog = catalog
		engine.rng = RandomService.create(1)
		engine.begin(player, enemy, "pipeline_%d" % quality, "pipeline")
		for step in range(29):
			engine.step()
		check(enemy.total_poison() == 0.0, "品质 %d：3 秒前不施加" % quality)
		engine.step()
		check(enemy.total_poison() == item.value_at(quality), "品质 %d：3 秒时施加对应中毒" % quality)
	var rng := RandomService.create(20261008)
	var state := RunState.create(catalog, rng)
	var shops := ShopService.new(catalog, rng)
	var definition := catalog.shop(&"gear_shop")
	var found := 0
	var silver := 0
	var invalid := 0
	for serial in range(2000):
		var stock := shops._generate(state, "pipeline/%d" % serial, definition)
		for slot in stock.slots:
			if slot.quality == 1:
				silver += 1
			if slot.item != null and slot.item.definition_id == &"poison_vial":
				found += 1
				if slot.quality != 1:
					invalid += 1
	check(found > 0, "装备铺自然出现砒霜")
	check(invalid == 0, "砒霜只在商店与配置交集的白银品质出现")
	check(silver > 1000 and silver < 1400, "8000 货位仍约 15% 白银")
	var app := AppRoot.new()
	app.setup(catalog)
	app.controller.new_trial(&"warrior", &"sturdy", 1)
	var fixed := app.controller.install_fixed_shop("__item_preview__", &"gear_shop", [[&"poison_vial", 0], [&"poison_vial", 1], [&"poison_vial", 2], [&"poison_vial", 3]])
	app.controller.open_shop("__item_preview__/gear_shop")
	check(fixed.slots.size() == 4 and app.current_page_node() is PageShop, "固定四品质预览商店已构建")
	app.free()
	print("物品流水线验证：通过 %d，失败 %d；自然商店砒霜 %d 件" % [passed, failed, found])
	quit(1 if failed > 0 else 0)
