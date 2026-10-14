class_name PageHome
extends PageBase
## 开局选择：职业、血统与开发测试入口。

var _profession: StringName = &"warrior"
var _bloodline: StringName = &"sturdy"
var _prof_buttons: Array[Button] = []
var _blood_buttons: Array[Button] = []


func build() -> void:
	var root := add_root("武道试炼原型 · 开局选择")
	var cols := UiKit.row(12)
	root.add_child(cols)

	var left := UiKit.panel("选择职业与血统")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lb := UiKit.body(left)
	# 主角立绘放在左栏顶部：不额外分栏，避免小窗口下三栏把选择按钮挤窄。
	var hero_row := UiKit.row(12)
	lb.add_child(hero_row)
	var portrait := UiKit.pixel_art(HeroArt.pose(HeroArt.POSE_HOME), Vector2(126, 188))
	portrait.name = "HeroPortrait"
	hero_row.add_child(portrait)
	var intro := UiKit.vbox(4)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(intro)
	intro.add_child(UiKit.label("轮回者", 18, UiKit.COL_ACCENT))
	intro.add_child(UiKit.label(
		"被主神空间征召的人。每次踏入武道世界，都要在有限的背包格数与十点战斗栏之间做取舍。",
		14, UiKit.COL_MUTED))
	intro.add_child(UiKit.label(
		"当前形象为单一素材，暂不随职业与血统变化。", 13, UiKit.COL_MUTED))
	lb.add_child(UiKit.label("职业（被动规则）", 16, UiKit.COL_ACCENT))
	_prof_buttons.clear()
	for id in catalog.profession_choices():
		var t := catalog.trait_by_id(id)
		var b := UiKit.button("%s：%s" % [t.display_name, t.description], _on_profession.bind(id))
		lb.add_child(b)
		_prof_buttons.append(b)
	lb.add_child(UiKit.spacer(8))
	lb.add_child(UiKit.label("血统（基础属性与被动）", 16, UiKit.COL_ACCENT))
	_blood_buttons.clear()
	for id2 in catalog.bloodline_choices():
		var t2 := catalog.trait_by_id(id2)
		var b2 := UiKit.button("%s：%s" % [t2.display_name, t2.description], _on_bloodline.bind(id2))
		lb.add_child(b2)
		_blood_buttons.append(b2)
	lb.add_child(UiKit.spacer(10))
	lb.add_child(UiKit.label("起始：青铜长刀（2 格）+ 30 货币，生命 100 + 血统修正", 14, UiKit.COL_MUTED))
	lb.add_child(UiKit.button("进入武道世界", _on_start))

	var right := UiKit.panel("开发测试入口")
	right.custom_minimum_size = Vector2(420, 0)
	cols.add_child(right)
	var rb := UiKit.body(right)
	rb.add_child(UiKit.label("测试入口只影响本次会话，不改变正式规则与数值。", 14, UiKit.COL_MUTED))
	rb.add_child(UiKit.button("随机游玩（真实商店与掉落）", _on_play.bind(DevTools.MODE_RANDOM)))
	rb.add_child(UiKit.button("三路线回放：正常成长", _on_play.bind(DevTools.MODE_REPLAY_NORMAL)))
	rb.add_child(UiKit.button("三路线回放：掉落不佳（全材料）", _on_play.bind(DevTools.MODE_REPLAY_LOW)))
	rb.add_child(UiKit.button("三路线回放：连续战败", _on_play.bind(DevTools.MODE_REPLAY_FAILURE)))
	rb.add_child(UiKit.button("战斗实验室（单步与快速计算）", _on_play.bind(DevTools.MODE_BATTLE_LAB)))
	rb.add_child(UiKit.button("参数检查", _on_validate))
	rb.add_child(UiKit.button("新版节点测试：武道", _on_card_test))
	rb.add_child(UiKit.spacer(10))

	root.add_child(UiKit.label("本次选择：", 15, UiKit.COL_MUTED))
	_apply_highlight()


func _on_profession(id: StringName) -> void:
	_profession = id
	_apply_highlight()


func _on_bloodline(id: StringName) -> void:
	_bloodline = id
	_apply_highlight()


func _apply_highlight() -> void:
	for i in _prof_buttons.size():
		_prof_buttons[i].modulate = UiKit.COL_ACCENT if catalog.profession_choices()[i] == _profession else Color.WHITE
	for j in _blood_buttons.size():
		_blood_buttons[j].modulate = UiKit.COL_ACCENT if catalog.bloodline_choices()[j] == _bloodline else Color.WHITE


func _on_start() -> void:
	ctrl.use_card_exploration = false
	ctrl.new_trial(_profession, _bloodline, DevTools.world_seed)


func _on_play(mode: StringName) -> void:
	ctrl.use_card_exploration = false
	ctrl.request_dev_mode(mode)
	ctrl.new_trial(_profession, _bloodline, DevTools.world_seed)


func _on_card_test() -> void:
	ctrl.use_card_exploration = true
	ctrl.request_dev_mode(DevTools.MODE_RANDOM)
	ctrl.new_trial(_profession, _bloodline, DevTools.world_seed)


func _on_validate() -> void:
	var problems := catalog.validate()
	if problems.is_empty():
		ctrl.message.emit("参数检查通过：%d 个定义资源" % (catalog.items.size() + catalog.skills.size() + catalog.enemies.size() + catalog.shops.size()))
		return
	ctrl.message.emit("参数检查发现 %d 项问题，详见输出" % problems.size())
	for p in problems:
		print("[参数检查] %s" % p)
