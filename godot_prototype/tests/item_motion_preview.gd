extends SceneTree
var states: Array[BattleItemState] = []
var tick := 0.0
var total := 0.0
var last_charge := 0

func _initialize() -> void:
	call_deferred("show_preview")

func show_preview() -> void:
	root.content_scale_size = Vector2i(1200,540)
	root.size = root.content_scale_size
	DisplayServer.window_set_size(root.size)
	var canvas := Control.new()
	canvas.theme = UiKit.make_theme()
	root.add_child(canvas)
	canvas.add_child(UiKit.overlay(GamePalette.BACKGROUND,Vector2(root.size)))
	canvas.add_child(UiKit.abs_label("物品状态动效 · 共用模板 v1",26,GamePalette.TEXT,Rect2i(30,20,1140,42)))
	canvas.add_child(UiKit.abs_label("冷却暗幕逐步退去 · 状态标记留在卡面内 · 不覆盖顶部属性及品质边框",17,GamePalette.MUTED,Rect2i(30,70,1140,34)))
	var definition := ContentCatalog.load_default().item(&"poison_vial")
	for index in range(6):
		var state := BattleItemState.new()
		state.base_cd_ms = 3000
		state.cooldown_remaining_ms = 2250
		state.base_value = 3
		state.effects = definition.effects
		if index in [1,5]: state.haste_ms = 10000
		if index in [2,5]: state.slow_ms = 10000
		if index == 3: state.freeze_ms = 10000
		states.append(state)
		var x := 35+index*195
		canvas.add_child(UiKit.abs_label(["自然冷却","加速 ×2","减速 ×0.5","冰冻 · 暂停","充能 · 跳进度","加速＋减速"][index],19,GamePalette.TEXT,Rect2i(x,135,190,35)))
		var card := ItemCard.new()
		card.position = Vector2(x+40,195)
		card.size = Vector2(84,168)
		card.configure({"definition":definition,"quality":1,"battle_state":state})
		canvas.add_child(card)
		canvas.add_child(UiKit.abs_label(["像素扫描水平线","白色流光 · 淡蓝微光","棕色流光 · 大小错落","冰蓝框＋错落大雪花","冷却线上汇聚闪光","两种流光并存"][index],15,GamePalette.MUTED,Rect2i(x,390,190,28)))
	canvas.add_child(UiKit.abs_label("同一件砒霜展示不同状态；循环演示不改正式数据。加速与减速并存时，按正常速度推进。",16,GamePalette.MUTED,Rect2i(30,455,1140,35)))
	canvas.add_child(UiKit.abs_label("充能展示每 1.2 秒跳进度一次；实际战斗仅在真实充能发生时播放。",16,GamePalette.MUTED,Rect2i(30,495,1140,30)))
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(1.28).timeout
		await RenderingServer.frame_post_draw
		quit(0 if root.get_texture().get_image().save_png("res://../outputs/item-motion-preview.png") == OK else 1)
	if "--capture-frames" in OS.get_cmdline_user_args():
		var directory := ProjectSettings.globalize_path("res://../.scratch/item-pipeline/motion-frames").simplify_path()
		DirAccess.make_dir_recursive_absolute(directory)
		for index in range(40):
			await create_timer(0.08).timeout
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(directory.path_join("%03d.png" % index)) != OK:
				quit(1)
				return
		quit()

func _process(delta: float) -> bool:
	if states.is_empty(): return false
	total += delta
	tick += delta
	while tick >= 0.1:
		tick -= 0.1
		for state in states:
			if state.freeze_ms == 0:
				state.cooldown_remaining_ms = maxi(0,state.cooldown_remaining_ms-state.natural_advance_ms(100))
			if state.cooldown_remaining_ms == 0:
				state.uses += 1
				state.cooldown_remaining_ms = state.base_cd_ms
	var sequence := int(total/1.2)
	if sequence != last_charge:
		last_charge = sequence
		states[4].cooldown_remaining_ms = maxi(0,states[4].cooldown_remaining_ms-1000)
		states[4].charge_visual_seq += 1
	return false
