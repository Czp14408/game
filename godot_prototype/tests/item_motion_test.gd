extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr(label)
func _initialize() -> void:
	var state := BattleItemState.new()
	state.base_cd_ms = 3000
	state.cooldown_remaining_ms = 1500
	var motion := ItemMotion.new()
	motion.configure(state,Rect2(0,0,56,112))
	motion.sync()
	check(motion.progress == 0.5,"CD 读取真实进度")
	check(motion.cooldown_line_y() == 56,"冷却水平线位于当前暗幕边界")
	state.freeze_ms = 1000
	motion._process(0.1)
	check(state.cooldown_remaining_ms == 1500 and state.freeze_ms == 1000,"动画不推进战斗冷却或控制时长")
	state.charge_visual_seq += 1
	state.cooldown_remaining_ms = 500
	motion.sync()
	check(motion.charge_age == 0 and is_equal_approx(motion.progress,5.0/6),"冰冻中真实充能也播放且立即更新进度")
	check(motion.cooldown_line_y() == 23,"充能后的水平线随真实进度立即跳变")
	motion._process(0.2)
	motion.sync()
	check(motion.charge_age == 0.2,"同一充能不重复播放")
	state.uses += 2
	motion.sync()
	check(motion.use_age == 0,"多重释放合并一次视觉闪光")
	check(motion.mouse_filter == Control.MOUSE_FILTER_IGNORE,"覆盖层不阻止点击悬停")
	motion.free()
	var definition := ContentCatalog.load_default().item(&"poison_vial")
	for span in [1,2,3]:
		var copy := definition.duplicate() as ItemDef
		copy.size = span
		var card := ItemCard.new()
		card.size = Vector2(56*span,112)
		card.configure({"definition":copy,"quality":1,"battle_state":state})
		check(card.motion != null and card.motion.size == card.card_rect.size,"三种尺寸共用卡内动效范围")
		check(card.motion.z_index < card.stat_layer.z_index,"顶部数值在动效上方")
		card.free()
	var shop := ItemCard.new()
	shop.size = Vector2(56,112)
	shop.configure({"definition":definition,"quality":1})
	check(shop.motion == null,"非战斗物品不显示冷却动效")
	shop.free()
	print("物品动效验证：通过 %d，失败 %d" % [passed,failed])
	quit(1 if failed else 0)
