extends SceneTree
## 三类构筑方向的阶段供给样本（GitHub Issue #8 / 验收条目 3 的证据）。
##
## 用法：
##   godot --headless --path . --script res://tests/build_samples.gd -- --out <输出目录>
##
## 覆盖武器护盾、持续伤害、治疗联动三个方向，每个方向给出「补强前 / 补强后 / 补强后＋方向技能」
## 三档，对第一阶段全部 9 种固定对手配置各打一场固定种子战斗。
##
## 供给来源只使用文档已登记的固定验证库存：
##   03 号节点：护身佩 10、短刃 6、回春装置 10、火油器 10；补给店：恢复品 6
##   主神空间：越战越勇 12、短刃 6、回春装置 10、毒针器 10
## 方向技能「火势护体」「回春护体」在固定验证库存中**没有来源**，本样本作为显式测试输入注入，
## 并单独标注，供后续决定是补供给还是调整内容，不在此处修改任何规则或数值。
##
## 退出码：0 无脚本错误；1 存在脚本错误（样本胜负本身不判失败，只如实记录）。

const DEFAULT_OUT_DIR := "D:/clawWorkSpace/game/_验证/复演账本"

## 9 种固定对手配置的稳定顺序
const TEMPLATES := [&"direct_attack", &"defense_heal", &"damage_over_time"]

const DIRECTIONS := [
	{
		"key": "weapon_shield", "title": "① 武器护盾方向",
		"supply": "起始青铜长刀；03 号节点固定库存护身佩(10)、短刃(6)；主神固定库存越战越勇(12)",
		"note": "越战越勇在「使用护盾」后成长全部武器本场伤害，与护身佩的「使用武器后自身充能」形成双向联动。",
		"variants": [
			{"label": "补强前：长刀＋护身佩＋短刃", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"short_blade", 0]], "skills": {}},
			{"label": "补强后：＋青铜越战越勇(12)", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"short_blade", 0]],
				"skills": {&"ever_stronger": 0}},
			{"label": "对照补强：第二件短刃合成白银短刃(6)", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"short_blade", 1]], "skills": {}},
			{"label": "对照补强：＋重锤(14)", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"heavy_hammer", 0]], "skills": {}},
			{"label": "上界参考：长刀＋白银护身佩＋短刃＋越战越勇", "profession": &"warrior",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 1], [&"short_blade", 0]],
				"skills": {&"ever_stronger": 0}},
		],
	},
	{
		"key": "damage_over_time", "title": "② 持续伤害方向",
		"supply": "03 号节点固定库存火油器(10)；主神固定库存毒针器(10)。战斗栏需 2＋2 格。",
		"note": "火油器灼烧、毒针器剧毒均为持续伤害，与技能「火势护体」（施加灼烧后获得护盾）联动；"
				+ "该技能在固定验证库存中无来源，此处作为显式测试输入注入。",
		"variants": [
			{"label": "补强前：长刀＋护身佩＋短刃", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"short_blade", 0]], "skills": {}},
			{"label": "纯持续伤害：长刀＋火油器＋毒针器", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"fire_oil", 0], [&"poison_needle", 0]], "skills": {}},
			{"label": "武器＋持续伤害：长刀＋短刃＋火油器＋毒针器", "profession": &"warrior",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"fire_oil", 0], [&"poison_needle", 0]],
				"skills": {}},
			{"label": "武器＋持续伤害＋火势护体", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"fire_oil", 0], [&"poison_needle", 0]],
				"skills": {&"flame_aegis": 0}},
			{"label": "满战斗栏：长刀＋短刃＋护身佩＋火油器＋毒针器＋越战越勇", "profession": &"warrior",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"ward_charm", 0], [&"fire_oil", 0],
						[&"poison_needle", 0]],
				"skills": {&"ever_stronger": 0}},
		],
	},
	{
		"key": "heal_synergy", "title": "③ 治疗联动方向",
		"supply": "03 号节点固定库存回春装置(10)；补给店恢复品(6)；主神固定库存回春装置(10)。",
		"note": "回春装置为战斗中治疗，与技能「回春护体」（治疗事件后获得护盾，满血也触发）联动，"
				+ "医者职业使每次计算治疗量 +2。该技能在固定验证库存中无来源，此处作为显式测试输入注入。",
		"variants": [
			{"label": "补强前：长刀＋护身佩＋短刃", "profession": &"warrior", "bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"ward_charm", 0], [&"short_blade", 0]], "skills": {}},
			{"label": "治疗站场：长刀＋回春装置＋护身佩（医者）", "profession": &"medic",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"rejuvenator", 0], [&"ward_charm", 0]], "skills": {}},
			{"label": "武器＋治疗：长刀＋短刃＋回春装置（医者）", "profession": &"medic",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"rejuvenator", 0]], "skills": {}},
			{"label": "武器＋治疗＋回春护体（技能无固定来源）", "profession": &"medic",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"rejuvenator", 0]],
				"skills": {&"rejuvenating_aegis": 0}},
			{"label": "满战斗栏：长刀＋短刃＋护身佩＋回春装置＋回春护体（医者）", "profession": &"medic",
				"bloodline": &"sturdy",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"ward_charm", 0], [&"rejuvenator", 0]],
				"skills": {&"rejuvenating_aegis": 0}},
			{"label": "满战斗栏＋吸血血统：长刀＋短刃＋护身佩＋回春装置", "profession": &"warrior",
				"bloodline": &"vampire",
				"items": [[&"long_blade", 0], [&"short_blade", 0], [&"ward_charm", 0], [&"rejuvenator", 0]],
				"skills": {&"rejuvenating_aegis": 0}},
		],
	},
]


func _initialize() -> void:
	var out_dir := DEFAULT_OUT_DIR
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]

	var samples := BuildSamples.new()
	samples.out_dir = out_dir
	samples.generate()
	print(samples.summary())
	var err := samples.write()
	if err != OK:
		push_error("写出样本失败：%s" % error_string(err))
	print("── 样本输出目录：%s" % out_dir)
	quit(1 if samples.failed > 0 else 0)


# ===========================================================================

class BuildSamples extends TestSuite:
	const SEED := 20261007
	const PLAYER_MAX_HP := 120.0

	var out_dir: String = DEFAULT_OUT_DIR
	var catalog: ContentCatalog
	var results: Array[Dictionary] = []

	func _init() -> void:
		suite_name = "R0 三类构筑方向样本"

	func generate() -> void:
		catalog = ContentCatalog.load_default()
		var set_ := catalog.stage_set(&"stage_01")
		note("引擎 %s，内容版本 %s，玩家最大生命 %.0f"
				% [Engine.get_version_info()["string"], catalog.content_version, PLAYER_MAX_HP])
		for d in DIRECTIONS:
			for v in (d["variants"] as Array):
				_run_variant(d, v, set_)

	func _run_variant(direction: Dictionary, variant: Dictionary, set_: StageSetDef) -> void:
		var rows: Array[Dictionary] = []
		var wins := 0
		for tpl_id in TEMPLATES:
			var tpl: StageTemplateDef = null
			for t in set_.templates:
				if t.template_id == tpl_id:
					tpl = t
					break
			if tpl == null:
				continue
			for extra in set_.extra_pool:
				var equipment: Array = []
				for g in tpl.equipment:
					equipment.append(g)
				if (extra as GrantDef).definition_id != &"":
					equipment.append(extra)
				var label := "%s＋%s" % [tpl.display_name, catalog.item_display((extra as GrantDef).definition_id)]
				var r := _battle(variant, set_, equipment, label)
				if r["win"]:
					wins += 1
				rows.append(r)
		results.append({
			"direction": direction["title"], "key": direction["key"],
			"supply": direction["supply"], "design_note": direction["note"],
			"variant": variant["label"], "rows": rows, "wins": wins, "total": rows.size(),
		})
		check(rows.size() == 9, "%s / %s 应打完 9 种固定对手配置" % [direction["title"], variant["label"]])

	func _battle(variant: Dictionary, set_: StageSetDef, equipment: Array, label: String) -> Dictionary:
		var items: Array = []
		var i := 0
		for pair in (variant["items"] as Array):
			items.append({"definition_id": pair[0], "quality": int(pair[1]), "instance_id": "p%d" % i})
			i += 1
		var player := CombatEngine.build_actor(catalog, {
			"side": CombatActor.SIDE_PLAYER, "display_name": "玩家",
			"max_hp": PLAYER_MAX_HP, "hp": PLAYER_MAX_HP,
			"profession": variant["profession"], "bloodline": variant["bloodline"],
			"items": items, "skills": (variant["skills"] as Dictionary).duplicate(),
		})
		var opponent := CombatEngine.build_stage_opponent(catalog, set_, equipment, label)
		var eng := CombatEngine.new()
		eng.catalog = catalog
		eng.rng = RandomService.create(SEED)
		eng.begin(player, opponent, "sample_%s" % label, "battle/sample")
		var res := eng.run_all()
		if res == null:
			check(false, "战斗未产出结果：%s" % label)
			return {"label": label, "win": false, "seconds": "—", "hp": 0, "enemy_hp": 0}
		return {
			"label": label, "win": res.winner_is_player(),
			"seconds": "%.0f" % res.time_seconds,
			"hp": int(res.player_hp), "enemy_hp": int(res.enemy_hp),
			"outcome": res.outcome_text(),
			"same_step": res.same_step_death,
		}

	# ------------------------------------------------------------------

	func write() -> Error:
		var mk := DirAccess.make_dir_recursive_absolute(out_dir)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return mk
		var f := FileAccess.open(out_dir.path_join("构筑方向样本.md"), FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(_to_markdown())
		f.close()
		var j := FileAccess.open(out_dir.path_join("构筑方向样本.json"), FileAccess.WRITE)
		if j == null:
			return FileAccess.get_open_error()
		j.store_string(JSON.stringify({
			"generated_at": Time.get_datetime_string_from_system(),
			"engine": Engine.get_version_info()["string"],
			"content_version": catalog.content_version,
			"seed": SEED, "player_max_hp": PLAYER_MAX_HP,
			"results": results,
			"assertions": {"passed": passed, "failed": failed, "failures": Array(failures)},
		}, "  "))
		j.close()
		return OK

	func _to_markdown() -> String:
		var out := PackedStringArray()
		out.append("# 三类构筑方向的阶段供给样本（R0 收尾 · Issue #8 验收条目 3）")
		out.append("")
		out.append("生成时间：%s｜引擎：%s｜内容版本：%s"
				% [Time.get_datetime_string_from_system(), Engine.get_version_info()["string"],
				catalog.content_version])
		out.append("")
		out.append("生成方式（可复现）：")
		out.append("")
		out.append("```bash")
		out.append("cd godot_prototype")
		out.append("/d/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . \\")
		out.append("  --script res://tests/build_samples.gd -- --out <输出目录>")
		out.append("```")
		out.append("")
		out.append("每个方向对第一阶段 9 种固定对手配置各打一场固定种子（%d）满血战斗；"
				% SEED)
		out.append("对手配置 = 3 种模板 × 3 种追加组件。玩家血统固定为强健，最大生命 120。")
		out.append("")
		out.append("**这些是固定玩家配置的覆盖检查，不是胜率估计。**")
		out.append("")
		var last_dir := ""
		for r in results:
			if r["direction"] != last_dir:
				last_dir = r["direction"]
				out.append("## %s" % last_dir)
				out.append("")
				out.append("- 供给来源：%s" % _first_of(last_dir, "supply"))
				out.append("- 设计意图：%s" % _first_of(last_dir, "design_note"))
				out.append("")
			out.append("### %s" % r["variant"])
			out.append("")
			out.append("| 对手配置 | 结果 | 耗时(秒) | 玩家剩余 | 对手剩余 | 备注 |")
			out.append("| --- | --- | --- | --- | --- | --- |")
			for row in (r["rows"] as Array):
				out.append("| %s | %s | %s | %d | %d | %s |" % [
					row["label"], "胜" if row["win"] else "负",
					row["seconds"], int(row["hp"]), int(row["enemy_hp"]),
					"同帧同死判负" if bool(row.get("same_step", false)) else ""])
			out.append("")
			out.append("小计：**%d/%d 胜**。" % [int(r["wins"]), int(r["total"])])
			out.append("")
		out.append("## 小结")
		out.append("")
		out.append(_conclusion())
		out.append("")
		out.append("## 脚本自身断言")
		out.append("")
		out.append("通过 %d，失败 %d。" % [passed, failed])
		for f2 in failures:
			out.append("- ✗ %s" % f2)
		out.append("")
		return "\n".join(out)

	func _first_of(direction_title: String, field: String) -> String:
		for r in results:
			if r["direction"] == direction_title:
				return r[field]
		return ""

	func _conclusion() -> String:
		var lines := PackedStringArray()
		for r in results:
			lines.append("- %s：%s → %d/%d 胜" % [r["direction"], r["variant"], int(r["wins"]), int(r["total"])])
		return "\n".join(lines)
