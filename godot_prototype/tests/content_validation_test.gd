class_name ContentValidationTest
extends TestSuite
## M0 验收：全部定义校验通过；参数检查覆盖引用、四档、占格、偶数价与概率和。

var catalog: ContentCatalog


func _init() -> void:
	suite_name = "M0 内容与参数检查"


func run() -> void:
	catalog = ContentCatalog.load_default()
	check(catalog.content_version != "unknown", "应读取 content_version")
	eq(catalog.items.size(), catalog.generated_item_ids.size(), "全部物品仅从 Excel 生成清单加载")
	check(catalog.items_from_excel, "已关闭旧物品配置来源")
	eq(catalog.skills.size(), 3, "独立被动技能数量")
	eq(catalog.traits.size(), 4, "职业与血统数量")
	eq(catalog.enemies.size(), 4, "敌人数量")
	eq(catalog.shops.size(), 5, "商店类型数量")
	eq(catalog.worlds.size(), 1, "世界数量")
	eq(catalog.stage_sets.size(), 1, "阶段集合数量")

	var problems := catalog.validate()
	check(problems.is_empty(), "参数检查应无问题，实际：%s" % [problems])

	# 四档数值抽查
	eq(catalog.item(&"long_blade").tier_values[3], 42.0, "长刀钻石伤害")
	eq(catalog.item(&"heavy_hammer").tier_values[0], 30.0, "重锤青铜伤害")
	eq(catalog.item(&"ward_charm").cooldown_ms, 5000, "护身佩 CD")
	eq(catalog.item(&"ward_charm").self_passive, ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE, "护身佩自身被动")

	# 标准价与出售回收
	eq(PriceTable.item_base_price(catalog.item(&"long_blade"), 0), 10, "青铜中型装备标准价")
	eq(PriceTable.item_base_price(catalog.item(&"heavy_hammer"), 3), 56, "钻石大型装备标准价")
	eq(PriceTable.item_sell_price(catalog.item(&"heavy_hammer"), 3), 28, "钻石大型装备回收 50%")
	eq(PriceTable.item_sell_price(catalog.item(&"scrap_material"), 0), 4, "材料出售价")
	eq(PriceTable.item_base_price(catalog.item(&"recovery_draught"), 0), 6, "恢复品购买价")
	eq(PriceTable.item_sell_price(catalog.item(&"recovery_draught"), 0), 3, "恢复品回收价")
	eq(PriceTable.skill_base_price(0), 12, "青铜技能标准价")
	eq(PriceTable.skill_sell_price(0), 0, "技能不能出售")

	# 世界结构
	var w: WorldDef = catalog.main_world()
	eq(w.nodes.size(), 18, "世界节点数量")
	eq(w.connections.size(), 22, "世界连接数量")
	eq(w.entry_node_id, "01", "免费入口节点")
	check(w.node_by_id("15").is_main_target, "15 号节点应为主线目标")
	check(w.node_by_id("05").has_container, "05 号节点应有容器")
	eq(w.quests.size(), 3, "主线 1 + 支线 2")
	for q in w.quests:
		check(q.reward_id != &"", "任务 %s 应有 reward_id" % q.quest_id)
	# 双向连接
	var forward := 0
	var backward := 0
	for c in w.connections:
		if c.node_a < c.node_b:
			forward += 1
		else:
			backward += 1
	eq(backward, 0, "连接应以节点编号升序存储，保证可双向遍历")

	# 守路条件作用于指定连接
	var guard_conn := w.connection_between("08", "11")
	check(guard_conn != null, "08—11 连接应存在")
	eq(guard_conn.guard_enemy_id, &"mountain_guard", "08—11 连接的守路敌人")
	check(w.connection_between("01", "02").guard_enemy_id == &"", "未守护的连接不应带守路条件")

	# 每条安全路线：入口到 15 都可达
	check(_reachable(w, "01", "15"), "入口到主线目标应可达")
	# 切断 08—11 后仍存在绕行（08—13—14—15）
	check(_reachable_without(w, "01", "15", ["08", "11"]), "存在绕开 08—11 的路线")

	# 商店品质概率与阶段模板占格
	var shop: ShopDef = catalog.shop(&"deity_mixed")
	var sum := 0.0
	for x in shop.quality_weights:
		sum += x
	near(sum, 1.0, 0.0001, "主神店品质概率和")
	eq(shop.item_count, 4, "每店商品数量")
	eq(shop.refresh_cost, 3, "刷新费")
	var stage: StageSetDef = catalog.stage_set(&"stage_01")
	eq(stage.templates.size(), 3, "阶段模板数量")
	eq(stage.extra_pool.size(), 3, "阶段追加组件数量")
	eq(stage.templates.size() * stage.extra_pool.size(), 9, "九种阶段对手配置")
	eq(stage.max_hp, 100.0, "阶段对手生命")


func _reachable(w: WorldDef, from: String, to: String) -> bool:
	return _bfs(w, from, to, [])


func _reachable_without(w: WorldDef, from: String, to: String, blocked_pair: Array) -> bool:
	return _bfs(w, from, to, blocked_pair)


func _bfs(w: WorldDef, from: String, to: String, blocked_pair: Array) -> bool:
	var seen := {from: true}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			return true
		for c in w.connections:
			if c.node_a != cur and c.node_b != cur:
				continue
			if blocked_pair.size() == 2 and c.connects(blocked_pair[0], blocked_pair[1]):
				continue
			var nxt := c.other(cur)
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return false
