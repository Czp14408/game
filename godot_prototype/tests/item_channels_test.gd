extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else:
		failed+=1
		printerr(label)
func make_state(catalog: ContentCatalog,seed_value: int) -> RunState:
	var state := RunState.create(catalog,RandomService.create(seed_value))
	state.world_id = &"wudao_01"
	state.current_node_id = "01"
	return state
func _initialize() -> void:
	var catalog := ContentCatalog.load_default()
	var rules: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reward_channels.json"))
	catalog.load_reward_rules(rules)
	check(catalog.validate().is_empty(),"Excel 编译渠道被运行时接受")
	var state := make_state(catalog,501)
	var encounter := EncounterService.new(catalog)
	encounter.bind(state.rng,QuestService.new(catalog),null)
	encounter.drop_override["test"] = "equipment"
	var found := 0
	for index in range(100):
		var es := EncounterState.new()
		es.encounter_key = "test/%d" % index
		es.node_id = "test"
		es.enemy_template_id = &"bandit"
		var summary := {"drops":[]}
		encounter._generate_drops(state,es,summary)
		for item in es.pending_drops:
			if item.definition_id==&"shield_dagger":
				found+=1
				check(item.quality in [1,2],"掉落品质限定为白银至黄金")
	check(found>0,"新物品通过真实敌人掉落入口出现")
	var world := WorldService.new(catalog)
	world.rng = state.rng
	var node_id := ""
	for node in catalog.worlds[&"wudao_01"].nodes:
		if node.container_table==&"material_small":node_id=node.node_id;break
	check(node_id!="","找到现有容器入口")
	var opened := world.open_container(state,node_id,"excel_test")
	check(opened.success and opened.data["drops"].size()==2,"保留容器原奖励并增加 Excel 奖励")
	var extra: ItemInstance = opened.data["drops"][1]
	check(extra.definition_id==&"shield_dagger" and extra.quality in [1,2],"容器奖励读取独立品质范围")
	var repeated := world.open_container(state,node_id,"excel_test")
	check(repeated.data["already"] and repeated.data["drops"][1]==extra,"重开容器不重抽、不重复生成")
	var quest := QuestService.new(catalog)
	state.quest_state(&"side_road_bandit").status = QuestState.STATUS_COMPLETED
	var money_before := state.money
	var claimed := quest.claim(state,&"side_road_bandit")
	check(claimed.success and state.money==money_before+6,"保留任务原金钱奖励")
	var awarded := state.instance(claimed.data["item_instance_id"])
	check(awarded!=null and awarded.definition_id==&"shield_dagger" and awarded.quality in [1,2],"任务物品奖励进入背包")
	check(not quest.claim(state,&"side_road_bandit").success,"任务奖励不能重复领取")
	var full := make_state(catalog,502)
	for index in range(10):
		var it := full.new_instance(&"short_blade",3)
		full.inventory.append(it)
	full.quest_state(&"side_road_bandit").status = QuestState.STATUS_COMPLETED
	var pending := quest.claim(full,&"side_road_bandit")
	check(pending.success and pending.data["item_pending"],"背包满时保留任务物品，不阻断任务完成")
	check(full.pending_quest_items.size()==1 and full.money==36,"容量不足不丢奖励，钱只发一次")
	check(not quest.claim(full,&"side_road_bandit").success,"保留物品期间仍防重复领奖")
	var inventory := InventoryService.new(catalog)
	check(inventory.discard(full,full.inventory[0].instance_id).success,"整理背包腾出空间")
	check(full.pending_quest_items.is_empty(),"腾出空间自动领取已保留物品")
	var rewards := 0
	for item in full.inventory:
		if item.definition_id==&"shield_dagger":rewards+=1
	check(rewards==1 and full.money==36,"补领只发一件，不再发金钱")
	print("新增获取渠道验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
