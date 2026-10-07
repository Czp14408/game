class_name RunController
extends RefCounted
## 页面切换、状态迁移、开局与结束。只保留一个当前试炼。
## 依据：游戏可玩原型技术方案.md 第 4/6/13 节。
##
## 边界：UI 提交命令，成功后监听状态变化刷新；禁止按钮直接修改金币、生命或物品数组。

signal page_requested(page: StringName, payload: Dictionary)
signal message(text: String)
signal battle_ready(engine: CombatEngine)

const PAGE_HOME := &"home"
const PAGE_WORLD_MAP := &"world_map"
const PAGE_MINIMAP := &"minimap"
const PAGE_PRE_BATTLE := &"pre_battle"
const PAGE_BATTLE := &"battle"
const PAGE_POST_BATTLE := &"post_battle"
const PAGE_SHOP := &"shop"
const PAGE_BUILD := &"build"
const PAGE_DEITY := &"deity"
const PAGE_STAGE_PREVIEW := &"stage_preview"
const PAGE_RESULT := &"result"
const PAGE_BATTLE_LAB := &"battle_lab"
const PAGE_PAUSE := &"pause"

var catalog: ContentCatalog
var rng: RandomService
var state: RunState
var world: WorldService
var economy: EconomyService
var quests: QuestService
var encounters: EncounterService
var inventory: InventoryService
var recorder: SessionRecorder

var current_page: StringName = PAGE_HOME
var active_shop_key: String = "deity/deity_mixed"
var active_encounter_key: String = ""
var active_engine: CombatEngine = null
var pending_dev_mode: StringName = DevTools.MODE_RANDOM
var dev_mode: StringName = DevTools.MODE_RANDOM
var last_battle_summary: Dictionary = {}
var last_result: BattleResult = null
var _page_entered_ms: int = 0
## 模态界面（构筑、商店）的返回位置，供界面内的「返回」按钮回到打开前的界面。
## 注意：Esc 只在战斗页生效（暂停/继续）；商店、构筑、大地图不响应 Esc，用页面内按钮返回。
var _build_return: StringName = PAGE_MINIMAP
var _shop_return: StringName = PAGE_MINIMAP

## 主界面 HUD 显示状态（供 page_minimap 读写，跨页面切换保留）：
## 状态栏（Tab 开关）与背包（B 开关）是否显示。
## Tab 联动：打开状态栏时同时显示背包，关闭状态栏后恢复此前背包开关状态。
## 这些只影响 HUD 叠加层显示，不改变物品/金币/世界进度，也不停止移动。
var _status_bar_open := false
var _bag_open := true
var _bag_open_before_tab := true


func start_new_app(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff
	rng = RandomService.create(seed_value)
	world = WorldService.new(catalog)
	world.rng = rng
	quests = QuestService.new(catalog)
	economy = EconomyService.new(catalog)
	encounters = EncounterService.new(catalog)
	inventory = economy.inventory
	_build_return = PAGE_MINIMAP
	_shop_return = PAGE_MINIMAP
	_set_page(PAGE_HOME)
	message.emit("选择职业与血统后进入武道世界")


# ---------------------------------------------------------------------------
# 开局
# ---------------------------------------------------------------------------

func new_trial(profession: StringName, bloodline: StringName, seed_value: int = -1) -> OperationResult:
	if seed_value >= 0:
		rng = RandomService.create(seed_value)
	state = RunState.create(catalog, rng)
	state.profession = profession
	state.bloodline = bloodline
	state.apply_traits()
	state.world_id = &"wudao_01"

	recorder = SessionRecorder.create("run_%d" % Time.get_unix_time_from_system())
	recorder.start({
		"engine": "4.7.2-stable",
		"content_version": catalog.content_version,
		"seed": str(rng.master_seed),
		"profession": String(profession),
		"bloodline": String(bloodline),
	})
	world.recorder = recorder
	quests.recorder = recorder
	economy.recorder = recorder
	encounters.bind(rng, quests, recorder)
	economy.bind_rng(rng)

	# 开局：青铜长刀 + 30 货币
	var blade := state.new_instance(&"long_blade", 0, "01")
	var r := inventory.pickup(state, blade)
	if not r.success:
		return OperationResult.fail(r.reason)
	var er := inventory.equip(state, blade.instance_id)
	if not er.success:
		return OperationResult.fail(er.reason)

	# 主线自动接取（位置仍未知）
	quests.accept(state, &"main_kill_chief")

	var wr := world.travel(state, catalog.main_world().entry_node_id)
	if not wr.success:
		return OperationResult.fail(wr.reason)
	_apply_dev_mode()
	if dev_mode == DevTools.MODE_BATTLE_LAB:
		_set_page(PAGE_BATTLE_LAB)
	else:
		_open_minimap()
	return OperationResult.ok({"node": state.current_node_id})


## 切换到开发测试模式：只改变显式测试输入，不修改规则与数值
func request_dev_mode(mode: StringName) -> void:
	pending_dev_mode = mode


func _apply_dev_mode() -> void:
	dev_mode = pending_dev_mode
	DevTools.mode = dev_mode
	encounters.drop_override = DevTools.drop_override()
	encounters.stage_override = DevTools.stage_override()
	var fixed := DevTools.fixed_shops()
	for key in fixed.keys():
		var parts := str(key).split("/")
		var ids: Array = []
		for s in (fixed[key]["items"] as Array):
			ids.append([StringName(s)])
		var skills: Array = []
		for s2 in (fixed[key]["skills"] as Array):
			skills.append([StringName(s2)])
		install_fixed_shop(parts[0], StringName(parts[1]), ids, skills)


## 安装固定验证库存（回放模式与开发测试专用）
func install_fixed_shop(node_id: String, shop_id: StringName, ids: Array, skills: Array = []) -> ShopState:
	var s := ShopState.new()
	s.shop_key = "%s/%s" % [node_id, shop_id]
	s.shop_id = shop_id
	for entry in ids:
		var slot := ShopState.Slot.new()
		var q: int = int(entry[1]) if entry.size() > 1 else 0
		slot.item = state.new_instance(entry[0], q)
		slot.item.location = ItemInstance.LOC_NONE
		slot.quality = q
		s.slots.append(slot)
	for entry2 in skills:
		var sslot := ShopState.Slot.new()
		sslot.is_skill = true
		sslot.skill_id = entry2[0]
		sslot.quality = int(entry2[1]) if entry2.size() > 1 else 0
		s.slots.append(sslot)
	state.node_state(node_id).shops[shop_id] = s
	return s


func surrender() -> OperationResult:
	if state == null or not state.is_running():
		return OperationResult.fail("试炼已结束")
	state.state = RunState.STATE_SURRENDERED
	_finish_run("认输")
	return OperationResult.ok()


# ---------------------------------------------------------------------------
# 世界导航
# ---------------------------------------------------------------------------

func travel_to(node_id: String) -> OperationResult:
	var r := world.travel(state, node_id)
	if not r.success:
		if r.reason.begins_with("连接被守路者封锁"):
			world.reveal_guard_reason(state, state.current_node_id, node_id)
		message.emit(r.reason)
		return r
	_open_minimap()
	return r


func open_world_map() -> void:
	if not state.is_running():
		return
	_set_page(PAGE_WORLD_MAP)


func close_world_map() -> void:
	_open_minimap()


# ---------------------------------------------------------------------------
# 主界面 HUD 状态（Tab 状态栏 / B 背包开关）
# ---------------------------------------------------------------------------

func status_bar_open() -> bool:
	return _status_bar_open


func bag_open() -> bool:
	return _bag_open


## Tab：切换状态栏。打开时联动显示背包；关闭时恢复此前背包开关状态。
## 不停止移动，不复制物品、不重新生成背包。
func toggle_status_bar() -> void:
	if _status_bar_open:
		# 关闭状态栏：恢复此前背包开关状态
		_status_bar_open = false
		_bag_open = _bag_open_before_tab
	else:
		# 打开状态栏：记录当前背包状态，并联动显示背包
		_bag_open_before_tab = _bag_open
		_status_bar_open = true
		_bag_open = true


## B：独立切换背包显示（不影响状态栏）。
func toggle_bag() -> void:
	_bag_open = not _bag_open
	# 手动切背包后，若状态栏当前开着，同步记录「此前背包状态」，供下次 Tab 关闭恢复
	if _status_bar_open:
		_bag_open_before_tab = _bag_open


func is_main_target_known() -> bool:
	return state.known_intel.has("chief_node") or state.node_state("15").discovered


func is_area_known() -> bool:
	return state.known_intel.has("bandit_area") or state.node_state("15").discovered


func talk_to(service: StringName) -> OperationResult:
	var r := world.talk(state, state.current_node_id, service, quests)
	if r.success:
		message.emit(str(r.data.get("text", "")))
	else:
		message.emit(r.reason)
	return r


func node_enemy_keys() -> Array[String]:
	return world.node_enemy_keys(state, state.current_node_id)


# ---------------------------------------------------------------------------
# 战前与战斗
# ---------------------------------------------------------------------------

func open_pre_battle(encounter_key: String) -> void:
	var es := encounters.ensure(state, state.current_node_id, encounter_key)
	active_encounter_key = encounter_key
	_set_page(PAGE_PRE_BATTLE, {"encounter": es})


func encounter_state() -> EncounterState:
	return state.node_state(state.current_node_id).encounter(active_encounter_key)


func cancel_battle() -> void:
	var es := encounter_state()
	if es != null:
		es.auto_prompt_suppressed = true
	_set_page(PAGE_MINIMAP)


func release_suppression() -> void:
	var es := encounter_state()
	if es != null:
		es.auto_prompt_suppressed = false


## 按遭遇键设置自动弹窗屏蔽（小地图离开接触区域时解除）
func set_suppression(encounter_key: String, suppressed: bool) -> void:
	if state == null or encounter_key == "":
		return
	var es := encounters.ensure(state, state.current_node_id, encounter_key)
	es.auto_prompt_suppressed = suppressed


func confirm_battle() -> OperationResult:
	if state == null or not state.is_running():
		return OperationResult.fail("试炼已结束")
	var es := encounter_state()
	if es == null:
		return OperationResult.fail("遭遇不存在")
	if es.defeated:
		return OperationResult.fail("该敌人已被击败")
	var engine := encounters.begin_battle(state, es, "world")
	active_engine = engine
	_set_page(PAGE_BATTLE, {"encounter": es})
	battle_ready.emit(engine)
	return OperationResult.ok({"battle_id": es.battle_id})


func settle_battle(engine: CombatEngine) -> Dictionary:
	var es := encounter_state()
	last_battle_summary = encounters.settle(state, es, engine)
	last_result = engine.result()
	recorder.record_event("battle_result", last_result.headline())
	if not state.is_running():
		_finish_run("累计 %d 次战败" % state.defeats)
	else:
		_set_page(PAGE_POST_BATTLE, {"summary": last_battle_summary})
	return last_battle_summary


## 结算但停留在当前战斗界面（胜利/失败结果与掉落都在同一战斗界面内展示，§3）。
## 与 settle_battle 共用结算核心，只是不跳转页面；掉落/技能待领取保留在 encounter 上。
func settle_battle_inplace(engine: CombatEngine) -> Dictionary:
	var es := encounter_state()
	last_battle_summary = encounters.settle(state, es, engine)
	last_result = engine.result()
	recorder.record_event("battle_result", last_result.headline())
	if not state.is_running():
		_finish_run("累计 %d 次战败" % state.defeats)
	return last_battle_summary


func resolve_skill_drop(learn: bool) -> OperationResult:
	var es := encounter_state()
	var r := encounters.resolve_skill_drop(state, es, learn, economy)
	message.emit("已学习技能" if r.success and learn else (r.reason if not r.success else "已放弃技能"))
	return r


func pickup_drops() -> Array[Dictionary]:
	var es := encounter_state()
	var r := encounters.pickup_pending(state, es)
	var got := 0
	for x in r:
		if bool(x["ok"]):
			got += 1
	message.emit("拾取 %d 件物品" % got)
	return r


func leave_post_battle() -> void:
	# 主线完成后仍可继续探索或回到主神空间
	_open_minimap()


## 重新进入战后界面（构筑整理返回时使用，复用已保存的结算摘要）
func reopen_post_battle() -> void:
	_set_page(PAGE_POST_BATTLE, {"summary": last_battle_summary})


## 战斗页面异常退出时的兜底返回
func close_battle() -> void:
	if state == null:
		_set_page(PAGE_HOME)
	elif state.returned_to_deity:
		open_deity()
	else:
		_open_minimap()


# ---------------------------------------------------------------------------
# 商店与构筑（模态界面：打开时暂停角色移动，返回时回到打开前的界面）
# ---------------------------------------------------------------------------

func open_shop(shop_key: String, return_to: StringName = PAGE_MINIMAP) -> void:
	active_shop_key = shop_key
	_shop_return = return_to
	_set_page(PAGE_SHOP, {"shop_key": shop_key})


func close_shop() -> void:
	var target := _shop_return
	_shop_return = PAGE_MINIMAP
	if target == PAGE_DEITY:
		open_deity()
	else:
		_set_page(PAGE_MINIMAP)


func open_build(return_to: StringName = PAGE_MINIMAP) -> void:
	if return_to != &"":
		_build_return = return_to
	_set_page(PAGE_BUILD)


func close_build() -> void:
	var target := _build_return
	_build_return = PAGE_MINIMAP
	match target:
		PAGE_PRE_BATTLE:
			open_pre_battle(active_encounter_key)
		PAGE_STAGE_PREVIEW:
			open_stage_preview()
		PAGE_POST_BATTLE:
			reopen_post_battle()
		PAGE_DEITY:
			open_deity()
		_:
			_set_page(PAGE_MINIMAP)


func current_shop() -> ShopState:
	var parts := active_shop_key.split("/")
	if parts.size() < 2:
		return null
	if parts[0] == "deity":
		return economy.shops.deity_shop(state)
	return economy.shops.state_for(state, parts[0], StringName(parts[1]))


func buy_slot(index: int) -> OperationResult:
	var r := economy.buy(state, current_shop(), index)
	message.emit("购买完成" if r.success else r.reason)
	return r


func sell(instance_id: String) -> OperationResult:
	var r := economy.sell(state, instance_id, active_shop_key)
	message.emit("出售完成" if r.success else r.reason)
	return r


func refresh_shop() -> OperationResult:
	var r := economy.refresh(state, current_shop())
	message.emit("已刷新商品" if r.success else r.reason)
	return r


func toggle_shop_lock() -> OperationResult:
	var s := current_shop()
	if s == null:
		return OperationResult.fail("商店无效")
	var r := economy.set_lock(state, s, not s.locked)
	message.emit("已锁定整批商品" if s.locked else "已解锁")
	return r


func equip(instance_id: String) -> OperationResult:
	var r := inventory.equip(state, instance_id)
	message.emit("已装备" if r.success else r.reason)
	return r


func unequip(instance_id: String) -> OperationResult:
	var r := inventory.unequip(state, instance_id)
	message.emit("已卸下" if r.success else r.reason)
	return r


func synthesize(a: String, b: String) -> OperationResult:
	var r := inventory.synthesize(state, a, b)
	message.emit("合成成功" if r.success else r.reason)
	return r


## 拖拽移动：来源/目标栏 + 目标格位。转发服务层，失败原因经 message 透出。
func move_item(instance_id: String, src: String, dst: String, target_index: int) -> OperationResult:
	var r := inventory.move_item(state, instance_id, src, dst, target_index)
	if r.success:
		message.emit("已移动物品")
	else:
		message.emit(r.reason)
	return r


## 商品拖拽购买：指定货位 + 目标栏 + 目标格位。
func buy_into(slot_index: int, dst: String, target_index: int) -> OperationResult:
	var r := economy.buy_into(state, current_shop(), slot_index, dst, target_index)
	if r.success:
		message.emit("购买完成")
	else:
		message.emit(r.reason)
	return r


## 出售（拖拽到售卖区）：沿用现有 sell，目标落区在界面层决定。
func sell_item(instance_id: String) -> OperationResult:
	return sell(instance_id)


## 入背包自动合成预览：给定一个物品定义+品质，返回若入包会发生的合成链结果
## （用于界面在拖入背包/购买时预览「最终品质/占格」）。只读，不改状态。
func preview_auto_synth(def_id: StringName, quality: int) -> Dictionary:
	if state == null:
		return {"merged": 0, "final_quality": quality, "changed": false}
	var it := state.new_instance(def_id, quality)
	# 构造只读预览：不真正提交，复用服务层校验逻辑
	var merged := 0
	var q := quality
	var inv: Array = state.inventory.duplicate()
	var guard := 0
	while guard < 64:
		guard += 1
		if q >= ContentCatalog.MAX_QUALITY:
			break
		var found := false
		for other in inv:
			var o := other as ItemInstance
			if o.definition_id == def_id and o.quality == q:
				inv.erase(o)
				q += 1
				merged += 1
				found = true
				break
		if not found:
			break
	return {"merged": merged, "final_quality": q, "changed": merged > 0}


func discard_item(instance_id: String) -> OperationResult:
	var r := inventory.discard(state, instance_id)
	message.emit("已丢弃" if r.success else r.reason)
	return r


func use_recovery(instance_id: String) -> OperationResult:
	var r := inventory.use_recovery(state, instance_id)
	message.emit("已使用恢复品，恢复 %d" % int(r.data.get("healed", 0)) if r.success else r.reason)
	return r


## 容器：开启一次生成一次，实物按容量拾取，容量不足时留在节点
func open_container_here(container_key: String) -> OperationResult:
	var r := world.open_container(state, state.current_node_id, container_key)
	if not r.success:
		message.emit(r.reason)
		return r
	if bool(r.data.get("already", false)):
		message.emit("这个容器已经搜刮过了")
		return r
	var drops: Array = r.data.get("drops", [])
	var got := 0
	var left := 0
	var merges := 0
	var landed: Array[String] = []     ## 最终落袋实例 id（合成时是产物，供界面闪光）
	for it in drops:
		var pr := inventory.pickup(state, it)
		if pr.success:
			got += 1
			var m := int(pr.data.get("merged", 0))
			merges += m
			landed.append(String(pr.data.get("instance_id", "")))
		else:
			left += 1
	r.data["landed_ids"] = landed
	r.data["merges"] = merges
	if left == 0:
		message.emit(("搜刮到 %d 件物品" % got) + ("（自动合成 ×%d）" % merges if merges > 0 else ""))
	else:
		message.emit("搜刮到 %d 件，另有 %d 件因背包空间不足留在原地" % [got, left])
	return r


# ---------------------------------------------------------------------------
# 主神整备与阶段挑战
# ---------------------------------------------------------------------------

func open_deity() -> void:
	encounters.ensure_stage_opponent(state)
	_set_page(PAGE_DEITY)


func return_to_deity() -> OperationResult:
	var r := world.return_to_deity(state)
	if not r.success:
		message.emit(r.reason)
		return r
	encounters.ensure_stage_opponent(state)
	_set_page(PAGE_DEITY)
	return r


func deity_heal() -> OperationResult:
	if state.current_hp >= state.max_hp:
		return OperationResult.fail("生命已满")
	state.set_hp(state.max_hp)
	recorder.record_event("deity_heal", {"hp": state.current_hp})
	return OperationResult.ok({"hp": state.current_hp})


func open_stage_preview() -> void:
	encounters.ensure_stage_opponent(state)
	_set_page(PAGE_STAGE_PREVIEW, {"opponent": state.stage_opponent})


func cancel_stage_preview() -> void:
	open_deity()


func open_battle_lab() -> void:
	_set_page(PAGE_BATTLE_LAB)


func confirm_stage_battle() -> OperationResult:
	if not state.is_running():
		return OperationResult.fail("试炼已结束")
	var engine := encounters.begin_stage_battle(state)
	active_engine = engine
	_set_page(PAGE_BATTLE, {"stage": true})
	battle_ready.emit(engine)
	return OperationResult.ok({"battle_id": state.stage_opponent.get("battle_id", "")})


func settle_stage_battle(engine: CombatEngine) -> Dictionary:
	var summary := encounters.settle_stage(state, engine)
	last_result = engine.result()
	recorder.record_event("stage_result", last_result.headline())
	if not state.is_running():
		_finish_run("累计 %d 次战败" % state.defeats)
	elif state.state == RunState.STATE_STAGE_COMPLETE:
		_finish_run("原型阶段完成")
	else:
		_set_page(PAGE_DEITY)
	return summary


# ---------------------------------------------------------------------------
# 收尾与统计
# ---------------------------------------------------------------------------

func _finish_run(reason: String) -> void:
	var summary := state.summary()
	var total := 0.0
	for k in recorder.timing.keys():
		total += float(recorder.timing[k])
	summary["reason"] = reason
	summary["timing_total_seconds"] = total
	recorder.finish(summary)
	# 试炼结束：清除本次试炼获得的物品、货币、技能与成长，不带入下一次试炼
	var final_state := state.state
	state.end_trial(final_state)
	_set_page(PAGE_RESULT, {"reason": reason, "summary": summary})


func _open_minimap() -> void:
	_set_page(PAGE_MINIMAP)


## 页面切换与耗时统计（统计模式互斥）
func _set_page(page: StringName, payload: Dictionary = {}) -> void:
	var now := Time.get_ticks_msec()
	if recorder != null:
		var elapsed := float(now - _page_entered_ms) / 1000.0
		if elapsed > 0.0:
			recorder.add_time(_bucket_of(current_page), elapsed)
	_page_entered_ms = now
	current_page = page
	page_requested.emit(page, payload)


func _bucket_of(page: StringName) -> String:
	match page:
		PAGE_WORLD_MAP:
			return "world_map"
		PAGE_MINIMAP:
			return "minimap_move"
		PAGE_PRE_BATTLE:
			return "pre_battle"
		PAGE_BATTLE:
			return "auto_battle"
		PAGE_SHOP:
			return "shop"
		PAGE_BUILD:
			return "build"
		PAGE_DEITY:
			return "deity"
		PAGE_STAGE_PREVIEW:
			return "stage_preview"
		_:
			return "other"
