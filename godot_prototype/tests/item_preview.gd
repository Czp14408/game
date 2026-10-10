extends Node
## 固定商品验证入口，不改正常游玩的资金和随机库存。
var catalog: ContentCatalog
var requested_id: StringName = &""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--preview-item")
	var id := requested_id
	if id == &"":
		id = StringName(args[index + 1] if index >= 0 and index + 1 < args.size() else "poison_vial")
	if catalog.item(id) == null:
		push_error("预览物品不存在：%s，请先更新 Excel 配置" % id)
		get_tree().quit(1)
		return
	var app := AppRoot.new()
	app.catalog = catalog
	get_tree().root.add_child.call_deferred(app)
	await get_tree().process_frame
	app.setup(catalog)
	var ctrl := app.controller
	ctrl.new_trial(&"warrior", &"sturdy", 20261008)
	ctrl.state.add_money(500)
	ctrl.install_fixed_shop("__item_preview__", &"gear_shop", [[id, 0], [id, 1], [id, 2], [id, 3]])
	ctrl.open_shop("__item_preview__/gear_shop")
	var back := Button.new()
	back.name = "PreviewReturn"
	back.text = "返回物品选择"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -180
	back.offset_right = -12
	back.offset_top = 1
	back.offset_bottom = 29
	back.pressed.connect(_return_to_hub.bind(app,id))
	app.add_child(back)
	print("[物品预览] 固定四档 %s；500 测试货币。此入口不代表自然商店的品质范围。" % id)

func _return_to_hub(app: AppRoot, id: StringName) -> void:
	var hub: Control = load("res://tests/item_preview_hub.gd").new()
	hub.set("catalog",catalog)
	hub.set("selected_id",id)
	get_tree().root.add_child.call_deferred(hub)
	app.queue_free()
	queue_free()
