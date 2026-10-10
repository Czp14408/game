extends Control
## Authoring preview only; does not register items, shops or rewards into production content.
var catalog: ContentCatalog
var selected_id: StringName = &""
var filtered_ids: Array[StringName] = []
var selector: OptionButton
var search: LineEdit
var details: Label
var holder: Control
var battle_button: Button
var shop_button: Button
var status: Label
var engines: Array[CombatEngine] = []
var cards: Array[ItemCard] = []
var summaries: Array[Label] = []
var playing := false
var accumulator := 0.0
var preview_step := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.make_theme()
	add_child(UiKit.overlay(GamePalette.BACKGROUND,Vector2(1280,720)))
	add_child(UiKit.abs_label("物品制作验收",28,GamePalette.TEXT,Rect2i(30,18,1220,44)))
	add_child(UiKit.abs_label("选择物品 → 核对四品质与悬停 → 播放战斗 → 进入商店购买和装备",17,GamePalette.MUTED,Rect2i(30,66,1220,32)))
	search = LineEdit.new()
	search.placeholder_text = "搜索物品名称或物品 ID"
	search.position = Vector2(30,115)
	search.size = Vector2(340,42)
	search.text_changed.connect(_filter_items)
	add_child(search)
	selector = OptionButton.new()
	selector.position = Vector2(390,115)
	selector.size = Vector2(620,42)
	selector.item_selected.connect(_selection_changed)
	add_child(selector)
	shop_button = Button.new()
	shop_button.text = "购买／装备验收"
	shop_button.position = Vector2(1030,115)
	shop_button.size = Vector2(220,42)
	shop_button.pressed.connect(open_shop_preview)
	add_child(shop_button)
	details = UiKit.abs_label("",16,GamePalette.MUTED,Rect2i(30,177,1220,40))
	add_child(details)
	holder = Control.new()
	holder.position = Vector2(30,230)
	holder.size = Vector2(1220,340)
	add_child(holder)
	battle_button = Button.new()
	battle_button.position = Vector2(30,583)
	battle_button.size = Vector2(250,44)
	battle_button.pressed.connect(_start_battle)
	add_child(battle_button)
	status = UiKit.abs_label("",16,GamePalette.TEXT,Rect2i(305,585,945,40))
	add_child(status)
	add_child(UiKit.abs_label("四品质均为固定预览；自然商店品质限制仍按配置执行。战斗演示使用无装备靶子。",16,GamePalette.MUTED,Rect2i(30,647,1220,32)))
	_filter_items("")
	if "--capture-preview" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().quit(0 if get_viewport().get_texture().get_image().save_png("res://../outputs/item-preview-hub.png") == OK else 1)

func _filter_items(query: String) -> void:
	selector.clear()
	filtered_ids.clear()
	var ids: Array = catalog.items.keys()
	ids.sort_custom(func(a, b):
		var a_new := catalog.generated_item_ids.has(a)
		var b_new := catalog.generated_item_ids.has(b)
		return String(a) < String(b) if a_new == b_new else a_new)
	for id: StringName in ids:
		var definition := catalog.item(id)
		if not query.strip_edges().is_empty() and not (String(id)+definition.display_name).to_lower().contains(query.strip_edges().to_lower()): continue
		filtered_ids.append(id)
		selector.add_item("%s · %s%s" % [definition.display_name,id,"（配置表）" if catalog.generated_item_ids.has(id) else ""])
	selector.disabled = filtered_ids.is_empty()
	if filtered_ids.is_empty():
		selected_id = &""
		_clear_samples()
		details.text = "未找到匹配物品；请确认物品已启用并成功更新配置。"
		battle_button.disabled = true
		shop_button.disabled = true
		status.text = "修改搜索内容后重试。"
		return
	var index := filtered_ids.find(selected_id)
	if index < 0: index = 0
	selector.select(index)
	_selection_changed(index)

func select_item(id: StringName) -> bool:
	var index := filtered_ids.find(id)
	if index < 0: return false
	selector.select(index)
	_selection_changed(index)
	return true

func _selection_changed(index: int) -> void:
	selected_id = filtered_ids[index]
	var definition := catalog.item(selected_id)
	details.text = "%s · %s物品 · 冷却 %s 秒 · 移到卡片上查看悬停说明" % [definition.display_name,["小","中","大"][clampi(definition.size-1,0,2)],String.num(definition.cooldown_ms/1000.0,2).trim_suffix(".0")]
	shop_button.disabled = false
	battle_button.disabled = not definition.is_active()
	battle_button.text = "播放 10 秒战斗演示"
	status.text = "四品质展示就绪。" if definition.is_active() else "该物品没有可播放的战斗效果，可检查卡面与商店。"
	_build_samples(false)

func _clear_samples() -> void:
	playing = false
	engines.clear()
	cards.clear()
	summaries.clear()
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

func _build_samples(battle: bool) -> void:
	_clear_samples()
	var definition := catalog.item(selected_id)
	for quality in range(4):
		var x := quality*305
		holder.add_child(UiKit.abs_label(PriceTable.quality_name(quality),20,GamePalette.QUALITIES[quality],Rect2i(x,0,290,36)))
		var card := ItemCard.new()
		card.position = Vector2(x+35,64)
		card.size = Vector2(56*definition.size,112)
		var entry := {"definition":definition,"quality":quality}
		if battle:
			var engine := CombatEngine.new()
			engine.catalog = catalog
			engine.rng = RandomService.create(20261009)
			var player := CombatEngine.build_actor(catalog,{"max_hp":100000,"hp":50000,"items":[{"definition_id":selected_id,"quality":quality}]})
			var target := CombatEngine.build_actor(catalog,{"side":1,"max_hp":10000000})
			engine.begin(player,target,"preview_%d" % quality,"preview")
			engines.append(engine)
			entry["battle_state"] = player.items[0]
		card.configure(entry)
		holder.add_child(card)
		cards.append(card)
		var summary := UiKit.abs_block("单次属性以顶部数值为准\n悬停可核对名称、TAG 与说明",15,GamePalette.MUTED,Rect2i(x,208,285,115))
		holder.add_child(summary)
		summaries.append(summary)

func _start_battle() -> void:
	if selected_id == &"" or not catalog.item(selected_id).is_active(): return
	_build_samples(true)
	preview_step = 0
	accumulator = 0
	playing = true
	battle_button.text = "重新播放战斗"
	_refresh_summaries()

func _advance_step() -> void:
	if not playing: return
	for engine in engines:
		if not engine.is_finished(): engine.step()
	preview_step += 1
	_refresh_summaries()
	if preview_step >= 100 or engines.all(func(engine): return engine.is_finished()):
		playing = false
		status.text = "演示结束 · %.1f 秒；可重新播放或进入购买／装备验收。" % (preview_step/10.0)

func _refresh_summaries() -> void:
	status.text = "战斗演示：%.1f / 10 秒 · 四品质分别独立计算" % (preview_step/10.0)
	for index in range(engines.size()):
		var state := engines[index].player_actor().items[0]
		var target := engines[index].enemy_actor()
		summaries[index].text = "释放：%d 次 · 剩余 CD：%.1f 秒\n累计攻击：%d · 获得护盾：%d\n当前中毒：%d · 灼烧：%d\n计算治疗：%d · 实际恢复：%d" % [state.uses,state.cooldown_remaining_ms/1000.0,state.damage_attack,state.shield_gained,target.total_poison(),target.total_burn(),state.heal_computed,state.heal_actual]

func _process(delta: float) -> void:
	if not playing: return
	accumulator += delta
	while accumulator >= CombatEngine.STEP_SECONDS and playing:
		accumulator -= CombatEngine.STEP_SECONDS
		_advance_step()

func open_shop_preview() -> void:
	if selected_id == &"": return
	playing = false
	var preview: Node = load("res://tests/item_preview.gd").new()
	preview.set("catalog",catalog)
	preview.set("requested_id",selected_id)
	get_tree().root.add_child.call_deferred(preview)
	queue_free()
