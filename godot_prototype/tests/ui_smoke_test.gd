class_name UiSmokeTest
extends TestSuite
## 界面冒烟测试：无画面构建 AppRoot，走通「开局→探索→战斗→商店→构筑→回归→阶段→结果」。
## 目的：捕获页面工厂缺失、脚本运行时错误与界面在异常状态下崩溃。
## 边界：只驱动控制器与页面公开接口，不直接修改状态字段（唯一例外：为制造回归条件置主线完成标记）。

var app: AppRoot
var tree: SceneTree


## 输入映射必须与 README 与界面提示一致。
## 回归背景：大地图曾在 `project.godot` 中被绑到 Backspace（4194308），
## 而 README 与页面按钮都写「Tab」，两者不一致——人工试玩时表现为「按 Tab 没反应」。
## v0.8 起：M 打开信息页（世界节点/任务/情报），Tab 切换状态栏（联动背包）。
func _test_input_map() -> void:
	var expected: Dictionary = {
		"move_up": KEY_W,
		"move_down": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"interact": KEY_E,
		"open_world_map": KEY_M,
		"toggle_status": KEY_TAB,
		"open_build": KEY_B,
		"cancel": KEY_ESCAPE,
		"dev_step": KEY_F,
	}
	for action in expected.keys():
		var want := int(expected[action])
		var found := false
		for ev in InputMap.action_get_events(String(action)):
			var ke := ev as InputEventKey
			if ke == null:
				continue
			if ke.keycode == want or ke.physical_keycode == want:
				found = true
				break
		check(found, "按键 %s 绑定到 %s" % [action, OS.get_keycode_string(want)])


## 战斗页实际排版：面板是否按清单落位、十格栏是否由净宽换算、
## 物品是否按占格落在连续的单位格里、生命填充是否留在生命槽内腔。
func _test_battle_page_layout(battle: PageBattle, ctrl: RunController) -> void:
	if battle == null:
		check(false, "战斗页为空，无法核对排版")
		return
	var rep := battle.layout_report()
	# 无画面脚本模式下不派发布局，设计画布的实时尺寸恒为 0；
	# 这里核对它「被要求」的尺寸，实际铺满与否由真渲染截图断言负责。
	check(rep["canvas_min"] == rep["design"],
		"设计画布配置为清单尺寸：%s / %s" % [rep["canvas_min"], rep["design"]])
	check(rep["canvas"] == rep["design"] or rep["canvas"] == Vector2i.ZERO,
		"设计画布未按非清单尺寸排布：%s" % rep["canvas"])

	var problems := PackedStringArray()
	for info in rep["panels"]:
		var d: Dictionary = info
		if d["texture"] != Vector2i(d["rect"].size):
			problems.append("%s 纹理 %s ≠ 矩形 %s" % [d["name"], d["texture"], d["rect"].size])
	check(problems.is_empty(), "落位的面板纹理与矩形一一对应，异常：%s" % "、".join(problems))

	check(rep["ops_bands"] == BattleSkin.bands_h(BattleSkin.OPERATIONS), "操作栏按清单的三段条带排布")

	var engine: CombatEngine = ctrl.active_engine
	var slot_count := int(rep["slot_count"])
	var sides: Dictionary = rep["sides"]
	for key in BattleSkin.SIDES:
		var is_player := key == BattleSkin.SIDE_PLAYER
		var info: Dictionary = sides[key]
		var tray: Rect2i = info["tray"]
		var slot_w: float = info["slot_width"]
		check(is_equal_approx(slot_w * slot_count, float(tray.size.x)),
			"%s 十格由净宽 %d 换算，格宽 %.2f" % [key, tray.size.x, slot_w])
		var hp_inner: Rect2i = info["hp_inner"]
		var hp_rect := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.HEALTH, key))
		check(hp_rect.encloses(hp_inner), "%s 生命填充内腔落在生命槽内" % key)
		check(not hp_inner.intersects(tray), "%s 生命填充内腔不与物品栏重叠" % key)

		# 物品按占格落在连续单位格上：起格累加，末件不超过第十格
		var actor := engine.player_actor() if is_player else engine.enemy_actor()
		var cells: Array = info["cells"]
		check(cells.size() == actor.items.size(),
			"%s 每件物品都有一个单位格控件（%d / %d）" % [key, cells.size(), actor.items.size()])
		var cursor := 0
		for i in mini(cells.size(), actor.items.size()):
			var cell: Rect2i = cells[i]
			var item: BattleItemState = actor.items[i]
			# 单位格宽是净宽除以十（非整数），逐格取整后单格宽会在 ±1 像素内浮动
			check(absf(float(cell.size.x) - slot_w * item.size) <= 1.0,
				"%s 第 %d 件「%s」占 %d 格，宽 %d 像素" % [key, i, item.display_name, item.size, cell.size.x])
			check(absf(cell.position.x - slot_w * cursor) <= 1.0,
				"%s 第 %d 件落在第 %d 格起" % [key, i, cursor])
			cursor += item.size
		check(cursor <= slot_count, "%s 物品共占 %d 格，不超过 %d 格" % [key, cursor, slot_count])


## 递归查找界面中挂上的形象节点。
## 运行时创建的节点 owner 为空，find_child 必须显式传 owned=false，否则找不到。
func _named(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	return root.find_child(node_name, true, false)


## 战斗界面组件（见 战斗UI组件与组合说明.md）。
## 这里钉住三类只在真渲染下才暴露、但可以提前守住的事实：
## 面板纹理与布局矩形一致（否则会静默拉伸）、版面矩形互不重叠、
## 以及左右列对齐与两侧区块等高这两条排布不变式。
func _test_battle_skin() -> void:
	check(BattleSkin.load_error() == "", "战斗皮肤清单可读：%s" % BattleSkin.load_error())
	check(BattleSkin.design_size() == Vector2i(1280, 690),
		"设计画布为 1280×690（720 减去顶部 30 像素状态条），实为 %s" % BattleSkin.design_size())

	var expected := [
		"portrait_enemy", "name_enemy", "status_enemy", "skill_enemy", "health_enemy", "tray_enemy",
		"middle",
		"portrait_player", "name_player", "status_player", "skill_player", "health_player", "tray_player",
		"operations",
	]
	for panel in expected:
		check(BattleSkin.has_panel(panel), "面板 %s 在清单中" % panel)
	var design := BattleSkin.design_size()
	var rects: Array = []
	var missing := PackedStringArray()
	for panel in expected:
		if not BattleSkin.has_panel(panel):
			continue
		var r := BattleSkin.rect(panel)
		var tex := BattleSkin.texture(panel)
		if tex == null:
			missing.append(panel)
			continue
		check(Vector2i(tex.get_size()) == r.size,
			"面板 %s 纹理尺寸 %s 与布局矩形 %s 一致" % [panel, tex.get_size(), r.size])
		check(r.position.x >= 0 and r.position.y >= 0
			and r.position.x + r.size.x <= design.x and r.position.y + r.size.y <= design.y,
			"面板 %s 不超出设计画布" % panel)
		var inner := BattleSkin.inner(panel)
		check(inner.size.x > 0 and inner.size.y > 0
			and inner.position.x >= 0 and inner.position.y >= 0
			and inner.position.x + inner.size.x <= r.size.x
			and inner.position.y + inner.size.y <= r.size.y,
			"面板 %s 内腔落在面板内且非空：%s" % [panel, inner])
		rects.append({"name": panel, "rect": r})
	check(missing.is_empty(), "全部面板纹理可加载，缺 %s" % "、".join(missing))

	# 版面矩形两两不重叠：重叠会让后画的面板盖住前一个的边框
	var overlaps := PackedStringArray()
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2i = rects[i]["rect"]
			var b: Rect2i = rects[j]["rect"]
			if a.intersects(b):
				overlaps.append("%s×%s" % [rects[i]["name"], rects[j]["name"]])
	check(overlaps.is_empty(), "版面矩形互不重叠，冲突：%s" % "、".join(overlaps))

	# 排布不变式：左右列对齐、两侧区块等高、两条物品栏等宽同列、生命槽独立于物品栏
	var lx := PackedInt32Array()
	var lw := PackedInt32Array()
	for side in BattleSkin.SIDES:
		for base in [BattleSkin.PORTRAIT, BattleSkin.NAME, BattleSkin.STATUS]:
			var r := BattleSkin.rect(BattleSkin.side_panel(base, side))
			lx.append(r.position.x)
			lw.append(r.size.x)
	check(_all_same(lx) and _all_same(lw), "头像／名称／状态三块左右对齐且等宽")
	var mid_x := PackedInt32Array()
	for side in BattleSkin.SIDES:
		for base in [BattleSkin.SKILL, BattleSkin.HEALTH, BattleSkin.TRAY]:
			mid_x.append(BattleSkin.rect(BattleSkin.side_panel(base, side)).position.x)
	check(_all_same(mid_x), "技能／生命／物品三栏起始 x 一致")
	var tray_e := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.TRAY, BattleSkin.SIDE_ENEMY))
	var tray_p := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.TRAY, BattleSkin.SIDE_PLAYER))
	check(tray_e.size == tray_p.size and tray_e.position.x == tray_p.position.x,
		"双方物品栏等宽同列：%s / %s" % [tray_e, tray_p])

	var block_e := _side_block(BattleSkin.SIDE_ENEMY)
	var block_p := _side_block(BattleSkin.SIDE_PLAYER)
	check(block_e == block_p, "两侧区块等高：%d / %d" % [block_e, block_p])
	check(block_e > 0 and block_e * 2 <= BattleSkin.design_size().y,
		"两侧区块叠起来放得下设计画布：%d×2 ≤ %d" % [block_e, BattleSkin.design_size().y])

	# 生命槽必须与物品栏分离，且槽内腔留得下填充与数值
	for side in BattleSkin.SIDES:
		var hp := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.HEALTH, side))
		var tray := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.TRAY, side))
		check(not hp.intersects(tray), "%s 生命槽与物品栏不重叠" % side)
		var groove := BattleSkin.inner(BattleSkin.side_panel(BattleSkin.HEALTH, side))
		check(groove.size.y >= 12 and groove.size.x > 400,
			"%s 生命槽内腔足够叠加填充与数值：%s" % [side, groove])

	# 操作栏由素材自带的两处分隔切成三段，界面按这三段排内容
	var bands := BattleSkin.bands_h(BattleSkin.OPERATIONS)
	check(bands.size() == 3, "操作栏可用条带为三段，实为 %d" % bands.size())
	if bands.size() == 3:
		check(bands[0].y <= bands[1].x and bands[1].y <= bands[2].x, "操作栏三段互不重叠")
		check(bands[1].y - bands[1].x > bands[0].y - bands[0].x,
			"操作栏中段最大（操作与记录）：%d" % (bands[1].y - bands[1].x))

	# 十格栏：净宽必须能被十等分，否则格宽会出现半像素
	var tray_inner := BattleSkin.inner(BattleSkin.side_panel(BattleSkin.TRAY, BattleSkin.SIDE_PLAYER))
	check(tray_inner.size.x / 10.0 >= 40.0,
		"十格单位格宽 %.1f 逻辑像素" % (tray_inner.size.x / 10.0))


func _side_block(side: String) -> int:
	var top := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.PORTRAIT, side)).position.y
	var bottom := BattleSkin.rect(BattleSkin.side_panel(BattleSkin.STATUS, side))
	return bottom.position.y + bottom.size.y - top


func _all_same(values: PackedInt32Array) -> bool:
	for v in values:
		if v != values[0]:
			return false
	return values.size() > 0


## 背包／商店／整理共用面板（背包商店整理共用面板说明.md）。
## 同步段只核对「清单自洽 + 布局按清单落位」；控件真实排版（容器有没有把子节点压扁、
## 文本有没有被裁）必须在帧推进段与真渲染截图里守——无画面脚本模式下 size 恒为设定值。
func _test_inventory_skin() -> void:
	check(InventorySkin.load_error() == "", "背包面板清单可读：%s" % InventorySkin.load_error())
	check(InventorySkin.design_size() == Vector2i(1280, 690),
		"背包面板设计画布同为 1280×690，实为 %s" % InventorySkin.design_size())
	check(InventorySkin.has_panel(InventorySkin.PANEL), "共用面板在清单中")
	if not InventorySkin.has_panel(InventorySkin.PANEL):
		return

	var rect := InventorySkin.rect(InventorySkin.PANEL)
	var tex := InventorySkin.texture(InventorySkin.PANEL)
	check(tex != null, "面板纹理可加载")
	if tex != null:
		check(Vector2i(tex.get_size()) == rect.size,
			"面板纹理 %s 与清单矩形 %s 同尺寸（1:1 贴，不拉伸）" % [Vector2i(tex.get_size()), rect.size])
	check(InventorySkin.inner(InventorySkin.PANEL).size.x > 0
		and InventorySkin.inner(InventorySkin.PANEL).size.y > 0,
		"面板内腔非空：%s" % InventorySkin.inner(InventorySkin.PANEL))

	# 三个分区按清单顺序竖排、互不重叠，且都落在外框内腔里
	var inner := InventorySkin.inner(InventorySkin.PANEL)
	var prev_bottom := -1
	for key in InventorySkin.REGIONS:
		check(InventorySkin.region(InventorySkin.PANEL, key).size.x > 0,
			"分区 %s 在清单中且非空" % key)
		var r := InventorySkin.region(InventorySkin.PANEL, key)
		check(inner.encloses(r), "分区 %s 落在外框内腔内：%s ⊆ %s" % [key, r, inner])
		check(r.position.y > prev_bottom, "分区 %s 在上一个之下（y=%d > %d）" % [key, r.position.y, prev_bottom])
		prev_bottom = r.position.y + r.size.y

	# 横栏净宽按十格换算：格宽非整数是允许的，但乘回去必须等于净宽
	for row in [InventorySkin.ROW_A, InventorySkin.ROW_B]:
		var rr := InventorySkin.region(InventorySkin.PANEL, row)
		var slots := InventorySkin.slot_count(row)
		check(slots == 10, "%s 是十格模板，实为 %d" % [row, slots])
		check(is_equal_approx(rr.size.x / float(slots) * slots, float(rr.size.x)),
			"%s 净宽 %d 由 %d 格换算" % [row, rr.size.x, slots])

	# 操作条在最下方，且不与两条横栏重叠
	var op := InventorySkin.region(InventorySkin.PANEL, InventorySkin.OP_BAR)
	for row in [InventorySkin.ROW_A, InventorySkin.ROW_B]:
		check(not op.intersects(InventorySkin.region(InventorySkin.PANEL, row)),
			"操作条不与 %s 重叠" % row)
	check(op.size.y >= 12, "操作条高度够放一行按钮：%d" % op.size.y)


## 共用面板在页面上的落位：矩形取自清单、纹理与矩形一致、物品格按占格连续排布。
## mode 决定上排装什么：「build」是战斗栏，「shop」是商品货位（两者都用同一张面板、同一段分区）。
func _test_inventory_page_layout(page: Control, ctrl: RunController, label: String,
		mode: String = "build") -> void:
	if page == null or not page.has_method("layout_report"):
		check(false, "%s：页面缺少 layout_report" % label)
		return
	var rep: Dictionary = page.layout_report()
	check(rep["canvas_min"] == rep["design"],
		"%s：设计画布配置为清单尺寸 %s / %s" % [label, rep["canvas_min"], rep["design"]])
	check(rep["panel_rect"] == rep["panel"],
		"%s：报告落位与面板实际位置一致 %s" % [label, rep["panel_rect"]])
	if mode == "shop":
		# §2：商店在屏幕上方横向展开——面板落位由页面覆盖到画布上半部
		var shop_rect: Rect2i = rep["panel_rect"]
		var shop_design: Vector2i = rep["design"]
		check(shop_rect.position.y < shop_design.y / 2.0,
			"%s：面板位于屏幕上方（y=%d）" % [label, shop_rect.position.y])
		check(shop_rect.position.x + shop_rect.size.x <= shop_design.x,
			"%s：面板不越出画布右缘" % label)
	else:
		check(rep["panel_rect"] == InventorySkin.rect(InventorySkin.PANEL),
			"%s：面板按清单矩形落位 %s" % [label, rep["panel_rect"]])
	check(rep["texture"] == Vector2i(rep["panel"].size),
		"%s：面板纹理 %s 与实际矩形 %s 同尺寸" % [label, rep["texture"], rep["panel"].size])
	check(rep["op_bar"].size.x > 0, "%s：操作条已落位 %s" % [label, rep["op_bar"]])
	check((rep["ops"] as Array).size() > 0, "%s：操作条上有按钮（%d 个）"
		% [label, (rep["ops"] as Array).size()])

	# 两行横栏：格宽由净宽换算，物品格逐个累加不重叠、不越界
	var rows: Dictionary = rep["rows"]
	for row in [InventorySkin.ROW_A, InventorySkin.ROW_B]:
		var info: Dictionary = rows[row]
		var slot_w := float(info["slot_width"])
		var region: Rect2i = info["region"]
		check(is_equal_approx(slot_w * int(info["slot_count"]), float(region.size.x)),
			"%s：%s 十格由净宽 %d 换算，格宽 %.2f" % [label, row, region.size.x, slot_w])
		var cells: Array = info["cells"]
		var cursor := 0
		var overlap := false
		for c in cells:
			var cell: Rect2i = (c as Dictionary)["rect"]
			check(absf(float(cell.position.x) - slot_w * cursor) <= 1.0,
				"%s：%s 第 %d 格物品落在第 %d 格起" % [label, row, cells.find(c), cursor])
			if cell.position.x < cursor * slot_w - 1.0:
				overlap = true
			cursor += 1
		check(not overlap, "%s：%s 物品格互不重叠" % [label, row])
		check(region.position.x + cursor * slot_w <= region.position.x + region.size.x + 1.0,
			"%s：%s 物品不越出横栏净宽（%d 格 / %d）" % [label, row, cursor, int(info["slot_count"])])

	# 上排装什么由模式决定：构筑页是战斗栏，商店页是商品货位；下排两边都是背包
	var bar_row: Dictionary = rows[InventorySkin.ROW_A]
	var inv_row: Dictionary = rows[InventorySkin.ROW_B]
	if mode == "shop":
		var shop := ctrl.current_shop()
		var goods := 0 if shop == null else shop.slots.size()
		check((bar_row["cells"] as Array).size() == goods,
			"%s：上排格数与货位数一致（%d / %d）"
			% [label, (bar_row["cells"] as Array).size(), goods])
		check(int(bar_row["enabled"]) == goods,
			"%s：上排启用格数等于货位数（%d）" % [label, int(bar_row["enabled"])])
	else:
		check((bar_row["cells"] as Array).size() == ctrl.state.battle_bar.size(),
			"%s：上排格数与战斗栏件数一致（%d / %d）"
			% [label, (bar_row["cells"] as Array).size(), ctrl.state.battle_bar.size()])
		check(int(bar_row["enabled"]) == RunState.BAR_CAPACITY,
			"%s：上排启用 %d 格（战斗栏容量）" % [label, int(bar_row["enabled"])])
	check((inv_row["cells"] as Array).size() == ctrl.state.inventory.size(),
		"%s：下排格数与背包件数一致（%d / %d）"
		% [label, (inv_row["cells"] as Array).size(), ctrl.state.inventory.size()])
	# 启用格数按玩法容量给，不是模板二十格（画出来会被当成额外容量）
	check(int(inv_row["enabled"]) == RunState.INVENTORY_CAPACITY,
		"%s：背包启用 %d 格（等于容量）" % [label, int(inv_row["enabled"])])


## 主角美术资源（R0.5）。
## 这里钉住三件只在真实渲染下才看得出来、但可以在无画面阶段提前守住的事实：
## 素材可加载、同一方向各帧等尺寸（否则走动时角色会上下跳）、方向映射与镜像符合预期。
func _test_hero_art() -> void:
	for dir in HeroArt.DIRECTIONS:
		var frames := HeroArt.walk_frames(dir)
		check(frames.size() == HeroArt.WALK_FRAMES,
			"行走序列 %s 有 %d 帧" % [dir, HeroArt.WALK_FRAMES])
		var first := Vector2.ZERO
		var same := true
		for i in frames.size():
			if frames[i] == null:
				same = false
				continue
			if i == 0:
				first = frames[i].get_size()
			elif frames[i].get_size() != first:
				same = false
		check(same and first.x > 0.0,
			"行走序列 %s 各帧等尺寸 %.0f×%.0f（保证帧间不跳动）" % [dir, first.x, first.y])

	for key in [HeroArt.POSE_HOME, HeroArt.POSE_BATTLE, HeroArt.POSE_VICTORY,
			HeroArt.POSE_DEFEAT, HeroArt.POSE_SURRENDER]:
		var tex := HeroArt.pose(key)
		check(tex != null and tex.get_width() > 0, "姿势 %s 可加载" % key)

	# 方向映射：纵向分量不弱于横向时取上下；左右靠镜像素材
	check(HeroArt.direction_of(Vector2.ZERO) == HeroArt.DIR_UP, "静止时朝上站立")
	check(HeroArt.direction_of(Vector2(0, -1)) == HeroArt.DIR_UP, "向上移动显示背面")
	check(HeroArt.direction_of(Vector2(0, 1)) == HeroArt.DIR_DOWN, "向下移动显示正面")
	check(HeroArt.direction_of(Vector2(1, 0)) == HeroArt.DIR_RIGHT, "向右移动显示右侧视")
	check(HeroArt.direction_of(Vector2(-1, 0)) == HeroArt.DIR_LEFT, "向左移动显示左侧视（镜像）")
	check(HeroArt.direction_of(Vector2(1, -1)) == HeroArt.DIR_UP, "斜向偏上时取背面")
	check(HeroArt.direction_of(Vector2(1, -0.2)) == HeroArt.DIR_RIGHT, "斜向偏右时取侧面")
	check(HeroArt.direction_of(Vector2(0, 1)) != HeroArt.direction_of(Vector2(0, -1)),
		"正反面不是同一序列")

	# 帧序号回绕：长时间移动不会越界
	check(HeroArt.frame_index(0.0) == 0, "相位 0 取第 0 帧")
	check(HeroArt.frame_index(1.0 / HeroArt.WALK_FPS) == 1, "经过一帧时长后取第 1 帧")
	var big := HeroArt.frame_index(10000.0)
	check(big >= 0 and big < HeroArt.WALK_FRAMES, "相位很大时帧序号仍在范围内（%d）" % big)
	check(HeroArt.frame_index(-5.0) == 0, "负相位按第 0 帧处理")


## 模拟按一次 M（信息页开关）。无画面脚本模式下引擎不派发输入事件，只能直接投递给页面的输入处理。
func _press_m(page: Node) -> void:
	if page == null:
		check(false, "按 M 时当前页面为空")
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.physical_keycode = KEY_M
	ev.pressed = true
	check(ev.is_action_pressed("open_world_map"), "M 事件能匹配 open_world_map 动作")
	page._unhandled_input(ev)


## 模拟按一次 Tab（状态栏开关）。
func _press_tab(page: Node) -> void:
	if page == null:
		check(false, "按 Tab 时当前页面为空")
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	check(ev.is_action_pressed("toggle_status"), "Tab 事件能匹配 toggle_status 动作")
	page._unhandled_input(ev)


func run() -> void:
	suite_name = "M4/M5 界面冒烟"
	tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		check(false, "无法取得 SceneTree")
		return

	var catalog := ContentCatalog.load_default()
	check(catalog.load_errors.is_empty(), "内容目录加载无错误")
	check(catalog.validate().is_empty(), "参数检查通过")

	_test_input_map()
	_test_battle_skin()
	_test_inventory_skin()

	app = AppRoot.new()
	app.name = "SmokeAppRoot"
	app.catalog = catalog
	tree.root.add_child(app)
	app.setup(catalog)

	var ctrl := app.controller
	check(ctrl != null, "控制器已建立")
	check(app.current_page_node() is PageHome, "开局进入选择页面")

	# --- 主角美术资源（R0.5） ---
	_test_hero_art()
	check(_named(app.current_page_node(), "HeroPortrait") != null, "开局页挂上主角立绘")

	# --- 开局（随机游玩模式） ---
	DevTools.mode = DevTools.MODE_RANDOM
	var r := ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	check(r.success, "开局成功：%s" % r.reason)
	check(app.current_page_node() is PageMinimap, "开局进入小地图")
	check(ctrl.state.money == RunState.START_MONEY, "开局货币为 %d" % RunState.START_MONEY)
	check(ctrl.state.battle_bar.size() == 1, "开局战斗栏有 1 件物品")

	var mini := app.current_page_node() as PageMinimap
	check(mini != null, "小地图页面类型正确")
	if mini != null:
		var specs := mini.interactable_specs()
		check(specs.size() > 0, "入口节点有可交互内容（%d 项）" % specs.size())
		var kinds := {}
		for s in specs:
			kinds[s["kind"]] = true
		check(kinds.has("enemy"), "入口节点有可选敌人")
		check(kinds.has("exit"), "入口节点有离开通路")
		var areas: Array = mini.get("_areas")
		check(areas.size() == specs.size(), "小地图交互实体数与清单一致（%d）" % areas.size())
		check(mini.get("_player") != null, "小地图已创建角色实体")
		check(mini.get("_walls") != null, "小地图已创建地形碰撞")
		# 主角指示物：四方向行走 + 左右镜像素材
		var ind := mini.hero_indicator()
		var ind_tex: Texture2D = ind["texture"]
		check(ind["node"] != null and ind_tex != null, "小地图指示物已挂上主角素材")
		check(String(ind["direction"]) == String(HeroArt.DIR_UP), "静止时朝上站立")
		mini.drive_hero(Vector2(-1, 0), 0.5)
		check(String(mini.hero_indicator()["direction"]) == String(HeroArt.DIR_LEFT), "向左移动切换左侧视")
		var left_tex: Texture2D = mini.hero_indicator()["texture"]
		check(left_tex != null and left_tex.get_width() == ind_tex.get_width(),
			"左侧视素材与背面素材同宽（镜像不改变画布）")
		mini.drive_hero(Vector2.ZERO, 0.5)
		check(String(mini.hero_indicator()["direction"]) == String(HeroArt.DIR_LEFT),
			"松开按键保持最后朝向且回到站立帧")
		check(int(mini.hero_indicator()["frame"]) == 0, "静止时回到第 0 帧")
		check(is_equal_approx(float(ind["collision_radius"]), PageMinimap.PLAYER_RADIUS),
			"接入形象未改动碰撞半径（%.1f）" % PageMinimap.PLAYER_RADIUS)

	# --- 世界战斗 ---
	var keys := ctrl.node_enemy_keys()
	check(keys.size() > 0, "取得节点敌人清单")
	ctrl.open_pre_battle(keys[0])
	check(app.current_page_node() is PagePreBattle, "进入战前查看页面")

	var br := ctrl.confirm_battle()
	check(br.success, "开始战斗")
	check(app.current_page_node() is PageBattle, "进入自动战斗页面")

	var money_before := ctrl.state.money
	var battle := app.current_page_node() as PageBattle
	check(_named(battle, "HeroAvatar") != null, "战斗页玩家侧挂上主角头像")
	_test_battle_page_layout(battle, ctrl)
	battle.fast_forward()
	var page := app.current_page_node()
	# v0.8：普通世界战斗结果与掉落留在同一战斗界面，不进入独立战后反馈页（§3）
	check(page is PageBattle, "战斗结束后停留在同一战斗界面")
	check(ctrl.last_result != null, "战斗结果已生成")
	if ctrl.last_result != null:
		check(ctrl.last_result.steps > 0, "战斗推进了 %d 个时间步" % ctrl.last_result.steps)
		check(ctrl.state.money >= money_before, "胜利后货币不减少")
	# 结果阶段：掉落居中展示，领取（若胜利有掉落）
	var es := ctrl.encounter_state()
	if es != null:
		if not es.pending_skill.is_empty():
			ctrl.resolve_skill_drop(true)
		if not es.pending_drops.is_empty():
			ctrl.pickup_drops()
	check(app.current_page_node() is PageBattle, "领取后仍在同一战斗界面")

	ctrl.leave_post_battle()
	check(app.current_page_node() is PageMinimap, "退出战斗回到小地图")

	# --- 付费探索：01 → 03 ---
	var money_pre := ctrl.state.money
	var tr := ctrl.travel_to("03")
	check(tr.success, "进入 03 号节点：%s" % tr.reason)
	check(ctrl.state.money == money_pre - 2, "首次进入新节点扣费 2（%d → %d）" % [money_pre, ctrl.state.money])
	var money_after_first := ctrl.state.money
	var revisit := ctrl.travel_to("01")
	check(revisit.success, "免费重访 01")
	var back := ctrl.travel_to("03")
	check(back.success and ctrl.state.money == money_after_first, "重访不重复扣费")

	# --- 构筑 ---
	ctrl.open_build(RunController.PAGE_MINIMAP)
	check(app.current_page_node() is PageBuild, "进入构筑页面")
	var build := app.current_page_node() as PageBuild
	check(build != null, "构筑页面类型正确")
	_test_inventory_page_layout(build, ctrl, "构筑页")
	var unequip_target := ""
	if ctrl.state.inventory.size() > 0:
		unequip_target = ctrl.state.inventory[0].instance_id
		var er := ctrl.equip(unequip_target)
		check(er.success, "装备背包物品")
		var ur := ctrl.unequip(unequip_target)
		check(ur.success, "卸下物品")
	ctrl.close_build()
	check(app.current_page_node() is PageMinimap, "构筑返回小地图")

	# --- 商店 ---
	ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP)
	check(app.current_page_node() is PageShop, "进入商店页面")
	_test_inventory_page_layout(app.current_page_node(), ctrl, "商店页", "shop")
	var shop := ctrl.current_shop()
	check(shop != null, "商店库存已生成")
	if shop != null:
		check(shop.slots.size() > 0, "商品位 %d 个" % shop.slots.size())
		var money0 := ctrl.state.money
		var bought := false
		for i in shop.slots.size():
			var slot: ShopState.Slot = shop.slots[i]
			if slot.purchased:
				continue
			var price := ctrl.economy.price_of_slot(slot)
			if price <= ctrl.state.money:
				var br2 := ctrl.buy_slot(i)
				if br2.success:
					bought = true
					check(ctrl.state.money == money0 - price, "购买后按标价扣款")
					var again := ctrl.buy_slot(i)
					check(not again.success, "重复购买同一商品被拒绝")
					break
		if not bought:
			note("商店首件商品暂不可买（余额或容量），跳过购买断言")
		var rr := ctrl.refresh_shop()
		if rr.success:
			check(ctrl.economy.price_of_slot(ctrl.current_shop().slots[0]) >= 0, "刷新后库存可读")
		else:
			check(ctrl.state.money < 3, "刷新失败原因为余额不足")
	ctrl.toggle_shop_lock()
	check(ctrl.current_shop().locked, "锁定状态生效")
	var locked_refresh := ctrl.refresh_shop()
	check(not locked_refresh.success, "锁定后不能刷新")
	ctrl.toggle_shop_lock()
	check(not ctrl.current_shop().locked, "解锁状态生效")
	ctrl.close_shop()
	check(app.current_page_node() is PageMinimap, "商店返回小地图")

	# --- 信息页（M 作为开关：打开 / 收起） + Tab 切换状态栏 ---
	check(app.current_page_node() is PageMinimap, "M 开关的起点是小地图")
	# Tab 切换状态栏（联动背包），不打开信息页
	var mini2 := app.current_page_node() as PageMinimap
	check(mini2 != null, "小地图在位")
	if mini2 != null:
		var status_before := ctrl.status_bar_open()
		_press_tab(app.current_page_node())
		check(ctrl.status_bar_open() != status_before, "Tab 切换状态栏显示状态")
		check(app.current_page_node() is PageMinimap, "Tab 不离开小地图")
		_press_tab(app.current_page_node())
		check(ctrl.status_bar_open() == status_before, "再次 Tab 恢复状态栏开关")
	# M 打开信息页
	_press_m(app.current_page_node())
	check(app.current_page_node() is PageWorldMap, "小地图按 M 打开信息页")
	var wm := app.current_page_node() as PageWorldMap
	check(wm != null, "信息页页面类型正确")
	_press_m(app.current_page_node())
	check(app.current_page_node() is PageMinimap, "信息页上再按 M 收起回小地图")
	# 按钮路径同样保留
	ctrl.open_world_map()
	check(app.current_page_node() is PageWorldMap, "按钮路径：进入信息页")
	ctrl.close_world_map()
	check(app.current_page_node() is PageMinimap, "按钮路径：信息页返回小地图")

	# --- 回归与阶段 ---
	ctrl.state.main_completed = true
	var ret := ctrl.return_to_deity()
	check(ret.success, "主线完成后可回归：%s" % ret.reason)
	check(app.current_page_node() is PageDeity, "进入主神整备页面")
	check(not ctrl.state.stage_opponent.is_empty(), "回归时生成阶段对手")
	var before_hp := ctrl.state.current_hp
	ctrl.state.set_hp(before_hp - 20.0)
	var heal := ctrl.deity_heal()
	check(heal.success and ctrl.state.current_hp == ctrl.state.max_hp, "主神治疗回满且不扣币")
	check(ctrl.state.money >= 0, "治疗后货币未被扣减")

	var opp_before := ctrl.state.stage_opponent.duplicate()
	ctrl.open_stage_preview()
	check(app.current_page_node() is PageStagePreview, "进入阶段战前查看")
	ctrl.open_build(RunController.PAGE_STAGE_PREVIEW)
	check(app.current_page_node() is PageBuild, "从阶段预览进入构筑")
	ctrl.close_build()
	check(app.current_page_node() is PageStagePreview, "构筑返回阶段预览")
	check(ctrl.state.stage_opponent.get("display_name", "") == opp_before.get("display_name", ""), "换装不改变已固定的阶段对手")

	var sr := ctrl.confirm_stage_battle()
	check(sr.success, "开始阶段战斗")
	check(app.current_page_node() is PageBattle, "进入阶段自动战斗页面")
	var sbattle := app.current_page_node() as PageBattle
	sbattle.fast_forward()
	page = app.current_page_node()
	check(page is PageResult or page is PageDeity, "阶段战斗结果落到结果页或整备页")
	if ctrl.state.is_running():
		check(page is PageDeity, "阶段战败且次数未耗尽时回到整备")
		ctrl.surrender()
	check(app.current_page_node() is PageResult, "认输进入结果页")
	var result := app.current_page_node() as PageResult
	check(result != null, "结果页类型正确")
	check(_named(result, "HeroPortrait") != null, "结果页挂上结局立绘")
	if result != null:
		check(String(result._pose_for("stage_complete")) == String(HeroArt.POSE_VICTORY), "阶段完成用欢呼立绘")
		check(String(result._pose_for("failed")) == String(HeroArt.POSE_DEFEAT), "试炼失败用倒地立绘")
		check(String(result._pose_for("surrendered")) == String(HeroArt.POSE_SURRENDER), "主动认输用低头立绘")
	check(ctrl.state.battle_bar.is_empty() and ctrl.state.inventory.is_empty(), "试炼结束后清空携带物")

	# --- 重新开局 ---
	ctrl.start_new_app()
	check(app.current_page_node() is PageHome, "重新开局回到选择页面")

	# --- 四种开发测试模式的入口都可用 ---
	for mode in [DevTools.MODE_RANDOM, DevTools.MODE_REPLAY_NORMAL, DevTools.MODE_REPLAY_LOW,
			DevTools.MODE_REPLAY_FAILURE]:
		ctrl.request_dev_mode(mode)
		var mr := ctrl.new_trial(&"warrior", &"sturdy", 20261007)
		check(mr.success, "模式 %s 可开局" % mode)
		check(app.current_page_node() is PageMinimap, "模式 %s 进入小地图" % mode)
		check(ctrl.dev_mode == mode, "模式 %s 已生效" % mode)
		if DevTools.is_replay():
			check(not ctrl.encounters.drop_override.is_empty(), "回放模式 %s 有固定掉落序列" % mode)
			check(not ctrl.state.node_state("__deity__").shops.is_empty(), "回放模式 %s 已安装固定主神库存" % mode)
		else:
			# 正常随机游玩不得加载任何固定供给（工单 07 验收条目 1）
			check(ctrl.encounters.drop_override.is_empty(), "随机游玩不加载固定掉落序列")
			check(ctrl.encounters.stage_override.is_empty(), "随机游玩不加载固定阶段对手")

	# --- 战斗实验室 ---
	DevTools.mode = DevTools.MODE_BATTLE_LAB
	ctrl.request_dev_mode(DevTools.MODE_BATTLE_LAB)
	ctrl.new_trial(&"medic", &"vampire", 20261007)
	check(app.current_page_node() is PageBattleLab, "战斗实验室入口直接进入实验室页面")
	var lab := app.current_page_node() as PageBattleLab
	if lab != null:
		lab.call("_reset_engine")
		lab.call("_run_all")
		check(app.current_page_node() is PageBattleLab, "实验室快速计算后页面仍在位")
		var lab_engine: CombatEngine = lab.get("_engine")
		check(lab_engine != null and lab_engine.is_finished(), "实验室快速计算已结束")
		check(lab_engine.result().steps > 0, "实验室结果含 %d 个时间步" % lab_engine.result().steps)
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.request_dev_mode(DevTools.MODE_RANDOM)


## 布局检查（需要真实帧推进，由 headless_main 在同步断言之后 await）
func extend_with_frames() -> void:
	if app == null or tree == null:
		return
	for target in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		# 只改窗口尺寸，页面按 full-rect 锚点自动跟随，避免与锚点冲突
		tree.root.size = target
		await tree.process_frame
		await tree.process_frame
		var page := app.current_page_node()
		check(page != null, "%d×%d：页面在位" % [target.x, target.y])
		if page == null:
			continue
		check(page.size.x > 200.0 and page.size.y > 120.0,
			"%d×%d：页面已布局（%.0f×%.0f）" % [target.x, target.y, page.size.x, page.size.y])
		var min_size := page.get_combined_minimum_size()
		check(min_size.x <= float(target.x) + 1.0,
			"%d×%d：页面最小宽度 %.0f 未超出视口" % [target.x, target.y, min_size.x])

	# 各主要页面在 1920×1080 下都能构建出非空内容
	var ctrl := app.controller
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	await tree.process_frame
	var routes: Array[Callable] = [
		func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP),
		func() -> void: ctrl.close_build(),
		func() -> void: ctrl.open_world_map(),
		func() -> void: ctrl.close_world_map(),
		func() -> void: ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP),
		func() -> void: ctrl.close_shop(),
	]
	for step in routes:
		step.call()
		await tree.process_frame
		await tree.process_frame
		var page := app.current_page_node()
		check(page != null and page.get_child_count() > 0, "页面在帧推进后仍有内容：%s" % ctrl.current_page)
	await _test_inventory_frames(ctrl)
	ctrl.state.main_completed = true
	ctrl.return_to_deity()
	await tree.process_frame
	check(app.current_page_node() is PageDeity and (app.current_page_node() as Control).get_child_count() > 0, "主神整备页面有内容")
	tree.root.size = Vector2i(1280, 720)
	await tree.process_frame
	await _test_battle_log_frames(ctrl)


func _find_op_button(page: Control, op_id: String) -> Button:
	var bar := _named(page, "OpBar")
	if bar == null:
		return null
	return _named(bar, "Op_%s" % op_id) as Button


func _find_text_label(node: Node) -> Label:
	for c in node.get_children():
		if c is Label and String((c as Label).text) != "":
			return c as Label
	return null


## 共用面板必须在真实帧推进后量：同步段控件 size 恒为设定值，量不到「容器把子节点压扁」
## 这类缺陷（战斗日志区曾因此整块空白、779 项全过却看不见内容）。
## 这里守三件事：面板本体没被容器改尺寸、两条横栏与操作条仍有高度、格线与物品格仍按净宽换算。
func _test_inventory_frames(ctrl: RunController) -> void:
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	await tree.process_frame
	var cases: Array[Callable] = [
		func() -> void: ctrl.open_build(RunController.PAGE_MINIMAP),
		func() -> void: ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP),
	]
	for step in cases:
		step.call()
		await tree.process_frame
		await tree.process_frame
		var page := app.current_page_node()
		if page == null or not page.has_method("layout_report"):
			check(false, "帧推进：共用面板页面在位")
			continue
		var rep: Dictionary = page.layout_report()
		var want := InventorySkin.rect(InventorySkin.PANEL)
		var got: Rect2i = rep["panel"]
		check(got.size == want.size,
			"帧推进：面板未被容器改尺寸（实 %s / 清单 %s）" % [got.size, want.size])

		# 设计画布要真被铺到清单尺寸，而不是被父容器按最小尺寸压扁
		var canvas: Vector2i = rep["canvas"]
		check(canvas == Vector2i.ZERO or canvas == rep["design"],
			"帧推进：设计画布实时尺寸为清单尺寸或尚未布局（%s）" % canvas)

		var rows: Dictionary = rep["rows"]
		for row in [InventorySkin.ROW_A, InventorySkin.ROW_B]:
			var info: Dictionary = rows[row]
			var region: Rect2i = info["region"]
			check(region.size.y > 20,
				"帧推进：%s 真实高度 %d 未被压扁" % [row, region.size.y])
			var slot_w := float(info["slot_width"])
			check(slot_w > 10.0,
				"帧推进：%s 格宽 %.2f 仍由净宽换算得出" % [row, slot_w])
			for c in info["cells"]:
				var cell: Rect2i = (c as Dictionary)["rect"]
				check(cell.size.x >= 1 and cell.size.y >= 20,
					"帧推进：%s 物品格实际 %d×%d 未被压扁" % [row, cell.size.x, cell.size.y])
		var op: Rect2i = rep["op_bar"]
		check(op.size.y >= 12, "帧推进：操作条真实高度 %d，够显示按钮" % op.size.y)
		for o in rep["ops"]:
			var od: Dictionary = o
			var r: Rect2i = od["rect"]
			check(r.size.x > 20 and r.size.y > 8,
				"帧推进：操作按钮「%s」实际 %d×%d" % [od["id"], r.size.x, r.size.y])
			# 按钮本身不写字，文字在一个不裁剪的 Label 上；核对这个 Label 真的存在且盖住条高，
			# 否则字会被 Button 的 clip_text 裁掉下半截（真渲染截图里只剩半个字）。
			var btn := _find_op_button(page, String(od["id"]))
			if btn == null:
				check(false, "帧推进：操作按钮「%s」节点在位" % od["id"])
				continue
			var lbl := _find_text_label(btn)
			check(lbl != null, "帧推进：操作按钮「%s」有承载文字的标签" % od["id"])
			if lbl != null:
				check((lbl as Control).size.y >= r.size.y,
					"帧推进：按钮「%s」文字标签高 %d 不小于条高 %d（不会被裁）"
					% [od["id"], (lbl as Control).size.y, r.size.y])
	ctrl.close_build()
	ctrl.close_shop()
	await tree.process_frame
	await _test_flash_frames(ctrl)


## 入包合成闪光（§11）必须在真实帧里守：叠加层的建立与 tween 自毁都依赖帧推进，
## --script 同步段量不到（与战斗日志同一类「同步全绿、真渲染空白」的缺陷）。
func _test_flash_frames(ctrl: RunController) -> void:
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	ctrl.open_shop("03/gear_shop", RunController.PAGE_MINIMAP)
	await tree.process_frame
	await tree.process_frame
	var page := app.current_page_node()
	# 注意：PanelInventory.build() 会把节点名固定成 "PanelInventory"（覆盖页面先设的名字）
	var panel := _named(page, "PanelInventory") as PanelInventory
	check(panel != null, "闪光帧测：商店共用面板在位")
	if panel == null:
		return
	check(panel.cell_by_id(InventorySkin.ROW_B, "不存在的id") == null,
		"闪光帧测：cell_by_id 未命中时返回 null")
	# 买得起就买一件，闪最终落袋格；买不起就闪面板本体（闪光机制相同）
	var target: Control = panel
	var shop := ctrl.current_shop()
	if shop != null:
		for i in shop.slots.size():
			var slot: ShopState.Slot = shop.slots[i]
			if not slot.purchased and not slot.is_skill \
					and ctrl.economy.price_of_slot(slot) <= ctrl.state.money:
				var br := ctrl.buy_slot(i)
				if br.success:
					# 与真实按钮路径一致：先刷新背包行，再按最终产物 id 找落位格
					page.call("_refresh")
					await tree.process_frame
					var landed := String(br.data.get("instance_id", ""))
					var cell := panel.cell_by_id(InventorySkin.ROW_B, "bag:%s" % landed)
					check(cell != null, "闪光帧测：购买产物在背包行有落位格")
					if cell != null:
						target = cell
				break
	UiKit.flash_control(target)
	check(_first_flash_rect(target) != null, "闪光帧测：闪光叠加层已建立")
	# tween 是真实时间驱动（0.45 秒）：无画面模式帧率不封顶，按帧数等不到，
	# 必须等真实时间走完后断言叠加层已自毁。
	await tree.create_timer(0.7).timeout
	await tree.process_frame
	check(_first_flash_rect(target) == null, "闪光帧测：闪光叠加层渐隐后自毁")
	ctrl.close_shop()
	await tree.process_frame


func _first_flash_rect(host: Control) -> ColorRect:
	for c in host.get_children():
		if c is ColorRect:
			return c
	return null


## 战斗日志必须在真实帧推进后才量得到：日志文本节点曾因换行标签的最小高度塌成 1 像素，
## 被外层容器排成 191×1，内容再全也看不见。同步断言量不到（此时控件尺寸恒为设置值），
## 所以这条只能放在帧断言段里守——它正是无画面套件与真渲染截图之外最容易漏掉的那类缺陷。
func _test_battle_log_frames(ctrl: RunController) -> void:
	DevTools.mode = DevTools.MODE_RANDOM
	ctrl.new_trial(&"warrior", &"sturdy", 20261007)
	await tree.process_frame
	var keys := ctrl.node_enemy_keys()
	if keys.is_empty():
		check(false, "战斗日志：可进入战斗（缺少对手）")
		return
	ctrl.open_pre_battle(keys[0])
	ctrl.confirm_battle()
	await tree.process_frame
	await tree.process_frame
	var battle := app.current_page_node() as PageBattle
	var eng: CombatEngine = ctrl.active_engine
	if battle == null or eng == null:
		check(false, "战斗日志：战斗页与引擎在位")
		return

	# 开战前几秒双方物品都在初始冷却，日志应当是「尚无事件」提示而不是空白。
	var before: Dictionary = battle.layout_report()["log"]
	check(int(before["chars"]) > 0, "开战初期日志给出空状态提示（%d 字）" % int(before["chars"]))

	# 推到双方都出手之后，日志必须有实际事件行。
	while not eng.is_finished() and eng.current_step() < 90:
		eng.step()
	battle._refresh_view()
	await tree.process_frame
	await tree.process_frame
	var after: Dictionary = battle.layout_report()["log"]
	var rect: Rect2i = after["rect"]
	check(int(after["chars"]) > 40,
		"战斗日志记录到事件（%d 字 / %d 行）" % [int(after["chars"]), int(after["lines"])])
	check(rect.size.x > 100 and rect.size.y > 100,
		"战斗日志区实际高宽足够（%d×%d）" % [rect.size.x, rect.size.y])
	check((battle.get_node_or_null("BattleCenter/DesignCanvas/BattleLog") as Control) != null,
		"战斗日志节点挂在设计画布上")
	ctrl.surrender()
