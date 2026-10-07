class_name ContentCatalog
extends RefCounted
## 内容目录：加载定义、按 ID 查询、数据校验。
## 边界：不保存玩家生命、库存或战斗状态。

const QUALITY_BRONZE := 0
const QUALITY_SILVER := 1
const QUALITY_GOLD := 2
const QUALITY_DIAMOND := 3
const MAX_QUALITY := 3

const ITEMS_DIR := "res://data/items"
const SKILLS_DIR := "res://data/skills"
const TRAITS_DIR := "res://data/traits"
const ENEMIES_DIR := "res://data/enemies"
const SHOPS_DIR := "res://data/shops"
const WORLDS_DIR := "res://data/worlds"
const STAGES_DIR := "res://data/stages"

var items: Dictionary = {}          # StringName -> ItemDef
var skills: Dictionary = {}         # StringName -> SkillDef
var traits: Dictionary = {}         # StringName -> TraitDef
var enemies: Dictionary = {}        # StringName -> EnemyDef
var shops: Dictionary = {}          # StringName -> ShopDef
var worlds: Dictionary = {}         # StringName -> WorldDef
var stage_sets: Dictionary = {}     # StringName -> StageSetDef
var content_version: String = "unknown"
var load_errors: PackedStringArray = []


static func load_default() -> ContentCatalog:
	var c := ContentCatalog.new()
	c.load_all()
	return c


func load_all() -> void:
	items = _load_dir(ITEMS_DIR)
	skills = _load_dir(SKILLS_DIR)
	traits = _load_dir(TRAITS_DIR)
	enemies = _load_dir(ENEMIES_DIR)
	shops = _load_dir(SHOPS_DIR)
	worlds = _load_dir(WORLDS_DIR)
	stage_sets = _load_dir(STAGES_DIR)
	_load_manifest()


func _load_dir(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_errors.append("目录不存在：%s" % dir_path)
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var res := ResourceLoader.load("%s/%s" % [dir_path, file_name])
		if res == null:
			load_errors.append("加载失败：%s/%s" % [dir_path, file_name])
			continue
		var id := _resource_id(res)
		if id == &"":
			load_errors.append("缺少定义 ID：%s/%s" % [dir_path, file_name])
			continue
		if out.has(id):
			load_errors.append("定义 ID 重复：%s" % id)
			continue
		out[id] = res
	return out


func _resource_id(res: Resource) -> StringName:
	if res is ItemDef:
		return (res as ItemDef).definition_id
	if res is SkillDef:
		return (res as SkillDef).definition_id
	if res is TraitDef:
		return (res as TraitDef).trait_id
	if res is EnemyDef:
		return (res as EnemyDef).template_id
	if res is ShopDef:
		return (res as ShopDef).shop_id
	if res is WorldDef:
		return (res as WorldDef).world_id
	if res is StageSetDef:
		return (res as StageSetDef).stage_id
	return &""


func _load_manifest() -> void:
	if not FileAccess.file_exists("res://data/content_manifest.json"):
		return
	var f := FileAccess.open("res://data/content_manifest.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and (parsed as Dictionary).has("content_version"):
		content_version = str((parsed as Dictionary)["content_version"])


func item(id: StringName) -> ItemDef:
	return items.get(id)


func skill(id: StringName) -> SkillDef:
	return skills.get(id)


func trait_by_id(id: StringName) -> TraitDef:
	return traits.get(id)


func enemy(id: StringName) -> EnemyDef:
	return enemies.get(id)


func shop(id: StringName) -> ShopDef:
	return shops.get(id)


func stage_set(id: StringName) -> StageSetDef:
	return stage_sets.get(id)


func all_item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in items.keys():
		out.append(k)
	out.sort()
	return out


func item_display(id: StringName) -> String:
	var d := item(id)
	return d.display_name if d != null else String(id)


func skill_display(id: StringName) -> String:
	var d := skill(id)
	return d.display_name if d != null else String(id)


func profession_choices() -> Array[StringName]:
	return _traits_of_kind(TraitDef.KIND_PROFESSION)


func bloodline_choices() -> Array[StringName]:
	return _traits_of_kind(TraitDef.KIND_BLOODLINE)


func _traits_of_kind(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in traits.keys():
		if (traits[k] as TraitDef).kind == kind:
			out.append(k)
	out.sort()
	return out


# ---------------------------------------------------------------------------
# 参数检查（开发测试入口：参数检查）
# ---------------------------------------------------------------------------

func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	problems.append_array(load_errors)

	for id in items.keys():
		var d: ItemDef = items[id]
		if d.tier_values.size() != 4:
			problems.append("物品 %s 的四档数值不完整" % id)
		if d.size < 1 or d.size > 3:
			problems.append("物品 %s 占格非法：%d" % [id, d.size])
		if d.equippable and d.size > 3:
			problems.append("物品 %s 超过战斗栏单件上限" % id)
		if d.cooldown_ms <= 0 and d.category != ItemDef.CAT_CONSUMABLE and d.category != ItemDef.CAT_MATERIAL:
			problems.append("物品 %s 缺少有效 CD" % id)
		for e in d.effects:
			if e.value_source == &"tier" and d.tier_values.size() != 4:
				problems.append("物品 %s 的效果缺少四档数值" % id)

	for id in skills.keys():
		var s: SkillDef = skills[id]
		if s.tier_values.size() != 4:
			problems.append("技能 %s 的四档数值不完整" % id)
		if s.trigger_event == &"":
			problems.append("技能 %s 未声明触发事件" % id)

	for id in enemies.keys():
		var e: EnemyDef = enemies[id]
		if e.max_hp <= 0.0:
			problems.append("敌人 %s 生命非法" % id)
		var total := 0
		for g in e.equipment:
			var d := item(g.definition_id)
			if d == null:
				problems.append("敌人 %s 引用了不存在的物品 %s" % [id, g.definition_id])
			else:
				total += d.size
			if g.quality < 0 or g.quality > MAX_QUALITY:
				problems.append("敌人 %s 的物品品质越界" % id)
		if total > 10:
			problems.append("敌人 %s 占格超过 10：%d" % [id, total])
		for g in e.skills:
			if skill(g.definition_id) == null:
				problems.append("敌人 %s 引用了不存在的技能 %s" % [id, g.definition_id])

	for id in shops.keys():
		var s: ShopDef = shops[id]
		var sum := 0.0
		for w in s.quality_weights:
			sum += w
		if absf(sum - 1.0) > 0.0001:
			problems.append("商店 %s 品质概率和不为 1：%f" % [id, sum])
		for pid in s.pool_ids():
			if item(pid) == null and skill(pid) == null:
				problems.append("商店 %s 引用了不存在的内容 %s" % [id, pid])
		if s.item_count <= 0:
			problems.append("商店 %s 商品数非法" % id)
		if s.mode == ShopDef.MODE_MIXED and absf(s.equipment_weight + s.skill_weight - 1.0) > 0.0001:
			problems.append("商店 %s 类别权重和不为 1" % id)

	for id in stage_sets.keys():
		var s: StageSetDef = stage_sets[id]
		if s.templates.is_empty() or s.extra_pool.is_empty():
			problems.append("阶段集合 %s 模板或追加池为空" % id)
		for t in s.templates:
			var total := t.total_size(self)
			if total > 10:
				problems.append("阶段模板 %s 占格超过 10：%d" % [t.template_id, total])
			for g in t.equipment:
				if item(g.definition_id) == null:
					problems.append("阶段模板 %s 引用了不存在的物品 %s" % [t.template_id, g.definition_id])
		for g in s.extra_pool:
			if item(g.definition_id) == null:
				problems.append("阶段集合 %s 的追加组件不存在：%s" % [id, g.definition_id])

	for wid in worlds.keys():
		var w: WorldDef = worlds[wid]
		var ids := {}
		for n in w.nodes:
			if ids.has(n.node_id):
				problems.append("世界 %s 节点 ID 重复：%s" % [wid, n.node_id])
			ids[n.node_id] = true
			for sid in n.shop_ids:
				if shop(sid) == null:
					problems.append("节点 %s 引用了不存在的商店 %s" % [n.node_id, sid])
			for eid in n.enemies:
				if enemy(eid) == null:
					problems.append("节点 %s 引用了不存在的敌人 %s" % [n.node_id, eid])
		if not ids.has(w.entry_node_id):
			problems.append("世界 %s 入口节点不存在：%s" % [wid, w.entry_node_id])
		for c in w.connections:
			if not ids.has(c.node_a) or not ids.has(c.node_b):
				problems.append("世界 %s 连接引用了不存在的节点：%s-%s" % [wid, c.node_a, c.node_b])
			if c.guard_enemy_id != &"" and enemy(c.guard_enemy_id) == null:
				problems.append("世界 %s 守路敌人不存在：%s" % [wid, c.guard_enemy_id])
		for q in w.quests:
			if q.target_enemy_id != &"" and enemy(q.target_enemy_id) == null:
				problems.append("任务 %s 引用了不存在的敌人 %s" % [q.quest_id, q.target_enemy_id])
			if q.reward_id == &"":
				problems.append("任务 %s 缺少 reward_id（无法防重复领奖）" % q.quest_id)
			if q.claim_mode == QuestDef.CLAIM_NPC and not ids.has(q.claim_node_id):
				problems.append("任务 %s 领奖节点不存在：%s" % [q.quest_id, q.claim_node_id])

	for id in items.keys():
		var d: ItemDef = items[id]
		for q in range(MAX_QUALITY):
			if PriceTable.item_base_price(d, q) % 2 != 0:
				problems.append("物品 %s 第 %d 档标准价不是偶数" % [id, q])
			if PriceTable.synthesis_is_profitable(d, q):
				problems.append("物品 %s 第 %d 档合成后出售可赚钱" % [id, q])

	return problems


func main_world() -> WorldDef:
	for k in worlds.keys():
		return worlds[k]
	return null
