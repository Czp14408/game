extends SceneTree

func _initialize() -> void:
	call_deferred("show_preview")

func show_preview() -> void:
	root.content_scale_size = Vector2i(1400,700)
	root.size = root.content_scale_size
	DisplayServer.window_set_size(root.size)
	var canvas := Control.new()
	canvas.theme = UiKit.make_theme()
	root.add_child(canvas)
	canvas.add_child(UiKit.overlay(GamePalette.BACKGROUND,Vector2(root.size)))
	canvas.add_child(UiKit.abs_label("物品悬停说明 · 当前工程实际模板",26,GamePalette.TEXT,Rect2i(30,20,1340,42)))
	canvas.add_child(UiKit.abs_label("名称不附带品质 · 品质由边框区分 · TAG 统一文字色 · 数值自动生成",17,GamePalette.MUTED,Rect2i(30,70,1340,34)))
	var definitions: Array[ItemDef] = [ContentCatalog.load_default().item(&"poison_vial"),load("res://tests/fixtures/combined_small.tres"),load("res://tests/fixtures/growth_blade.tres")]
	for index in range(3):
		var card := ItemCard.new()
		var quality: int = [0,2,0][index]
		var data := {"definition":definitions[index],"quality":quality}
		if index == 2:
			var battle := BattleItemState.new()
			battle.base_value = 8
			battle.battle_growth = 5
			data["battle_state"] = battle
		card.size = Vector2(112,112)
		card.configure(data)
		canvas.add_child(card)
		card.hide()
		var x := 30+index*455
		canvas.add_child(UiKit.abs_label(["砒霜 · 基础物品","组合属性 · 测试示例","铁刃 · 使用一次后"][index],21,GamePalette.TEXT,Rect2i(x,130,430,36)))
		var tooltip := card._make_custom_tooltip("") as Control
		tooltip.position = Vector2(x,185)
		canvas.add_child(tooltip)
	canvas.add_child(UiKit.abs_label("组合属性与铁刃仅用于展示排版；实际说明直接复用游戏中的悬停组件。",17,GamePalette.MUTED,Rect2i(30,620,1340,40)))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		quit(0 if root.get_texture().get_image().save_png("res://../outputs/item-tooltip-preview.png") == OK else 1)
