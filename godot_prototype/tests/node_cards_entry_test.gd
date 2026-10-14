extends SceneTree


func _initialize() -> void:
	var catalog := ContentCatalog.load_default()
	var ctrl := RunController.new()
	ctrl.catalog = catalog
	ctrl.use_card_exploration = true
	ctrl.start_new_app(13)
	assert(ctrl.new_trial(&"warrior", &"sturdy", 13).success)
	var state := ctrl.state
	assert(state.card_exploration and state.exploration_time == 11)
	var money := state.money
	assert(ctrl.world.travel(state, "02").success)
	assert(state.money == money and state.exploration_time == 10)
	assert(ctrl.world.travel(state, "01").success)
	assert(state.exploration_time == 10)
	state.exploration_time = 0
	assert(ctrl.world.travel(state, "02").success)
	assert(not ctrl.world.travel(state, "03").success)
	assert(state.money == money and state.current_node_id == "02")
	var service := NodeCardService.new()
	var ns := NodeState.new()
	var specs: Array[Dictionary] = [{"kind":"container", "key":"box", "label":"箱子"}, {"kind":"npc", "key":"person", "label":"人物"}]
	service.initialize(ns, specs)
	assert(not service.accessible(ns, "container:box"))
	assert(not service.move(ns, "container:box", 2).success)
	assert(service.move(ns, "cover:box", 2).success)
	assert(service.accessible(ns, "container:box"))
	assert(not service.move(ns, "npc:person", 0).success)
	var snapshot := ns.card_lanes.duplicate(true)
	service.initialize(ns, specs)
	assert(ns.card_lanes == snapshot)
	assert(not service.move(ns, "cover:box", 1).success)
	state.node_states[state.current_node_id] = ns
	assert(not ctrl.open_container_here("missing").success)
	var page := PageNodeCards.new(ctrl)
	state.node_states.clear()
	page.ensure_built()
	assert(page.board.get_child_count() > 0)
	if OS.get_cmdline_user_args().has("--capture"):
		root.add_child(page)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		assert(image.save_png("res://../outputs/node-cards-entry.png") == OK)
	page.free()
	print("New node entry: time, top-only access, fixed objects, revisit and UI construction passed.")
	quit(0)
