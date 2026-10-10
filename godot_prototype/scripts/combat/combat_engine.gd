class_name CombatEngine
extends RefCounted
## 固定步长战斗引擎。不引用 UI、物理节点或动画。
## 依据：游戏可玩原型技术方案.md 第 7 节；游戏核心规则定稿.md 第 3 节。

const STEP_MS := 100
const STEP_SECONDS := 0.1
const MAX_STEPS := 2000                 # 200 秒上限，仅作为计算安全边界
const STORM_START_STEP := 300           # 第 30 秒开始沙尘暴
const DOT_INTERVAL_STEPS := 10          # 每秒跳伤
const CHARGE_MS := 1000                 # 充能 1 秒（护身佩自身被动）
const STORM_BASE_DAMAGE := 5.0
const STORM_STEP_INCREMENT := 5.0
const CRIT_CHANCE := 0.0                # 本批内容没有暴击来源
const CRIT_MULTIPLIER := 2.0
const TIMELINE_EVERY_STEPS := 1

var catalog: ContentCatalog
var rng: RandomService

var _player: CombatActor
var _enemy: CombatActor
var _result: BattleResult
var _step: int = 0
var _finished: bool = false
var _outcome: StringName = BattleResult.OUTCOME_TIMEOUT
var _same_step_death: bool = false
var _event_seq: int = 0
var _side_events: Array = [[], []]      # 待处理的连锁事件（分侧）
var _rng_scope: String = ""


static func build_actor(p_catalog: ContentCatalog, spec: Dictionary) -> CombatActor:
	var a := CombatActor.new()
	a.side = int(spec.get("side", CombatActor.SIDE_PLAYER))
	a.display_name = str(spec.get("display_name", ""))
	a.profession = spec.get("profession", &"")
	a.bloodline = spec.get("bloodline", &"")
	a.skills = (spec.get("skills", {}) as Dictionary).duplicate()
	a.max_hp = float(spec.get("max_hp", RunState.BASE_MAX_HP))
	a.hp = float(spec.get("hp", a.max_hp))
	a.shield = 0.0

	var p := p_catalog.trait_by_id(a.profession)
	if p != null:
		match p.effect_type:
			TraitDef.EFFECT_WEAPON_DAMAGE_FLAT:
				a.weapon_damage_flat += p.effect_amount
			TraitDef.EFFECT_HEAL_COMPUTED_FLAT:
				a.heal_computed_flat += p.effect_amount
			TraitDef.EFFECT_MAX_HP_FLAT:
				pass  # max_hp 已由 RunState.apply_traits() 算进 spec，此处不重复叠加
			TraitDef.EFFECT_HEAL_ON_WEAPON_USE:
				a.heal_on_weapon_use += p.effect_amount
	var b := p_catalog.trait_by_id(a.bloodline)
	if b != null:
		match b.effect_type:
			TraitDef.EFFECT_WEAPON_DAMAGE_FLAT:
				a.weapon_damage_flat += b.effect_amount
			TraitDef.EFFECT_HEAL_COMPUTED_FLAT:
				a.heal_computed_flat += b.effect_amount
			TraitDef.EFFECT_MAX_HP_FLAT:
				pass  # 同上：由 spec.max_hp 提供
			TraitDef.EFFECT_HEAL_ON_WEAPON_USE:
				a.heal_on_weapon_use += b.effect_amount

	for raw in spec.get("items", []):
		var s := raw as Dictionary
		var def := p_catalog.item(s.get("definition_id", &""))
		if def == null:
			continue
		var st := BattleItemState.new()
		st.instance_id = str(s.get("instance_id", "%s#%d" % [def.definition_id, a.items.size()]))
		st.definition_id = def.definition_id
		st.display_name = def.display_name
		st.category = def.category
		st.size = def.size
		st.quality = int(s.get("quality", 0))
		st.effects = def.effects
		st.multicast = def.multicast_at(st.quality)
		st.weapon_growth_per_use = def.weapon_growth_at(st.quality)
		st.self_passive = def.self_passive
		st.base_cd_ms = def.cooldown_ms
		st.base_value = def.value_at(st.quality) + float(s.get("extra_value", 0.0)) + float(s.get("trial_growth", 0.0))
		st.cooldown_remaining_ms = def.cooldown_ms
		a.items.append(st)
	return a


## 由敌人定义构建战斗一方（等级/强化/技能均来自定义）
static func build_enemy(p_catalog: ContentCatalog, def: EnemyDef) -> CombatActor:
	var items := []
	var idx := 0
	for g in def.equipment:
		items.append({
			"definition_id": g.definition_id,
			"quality": g.quality,
			"extra_value": g.extra_value,
			"instance_id": "enemy_%s_%d" % [def.template_id, idx],
		})
		idx += 1
	var skills := {}
	for g in def.skills:
		skills[g.definition_id] = g.quality
	return build_actor(p_catalog, {
		"side": CombatActor.SIDE_ENEMY,
		"display_name": def.display_name,
		"max_hp": def.max_hp,
		"hp": def.max_hp,
		"skills": skills,
		"items": items,
	})


## 由阶段对手配置（模板 + 追加组件）构建战斗一方
static func build_stage_opponent(p_catalog: ContentCatalog, stage_set: StageSetDef, equipment: Array, display_name: String) -> CombatActor:
	var items := []
	var idx := 0
	for g in equipment:
		var grant := g as GrantDef
		items.append({
			"definition_id": grant.definition_id,
			"quality": grant.quality,
			"extra_value": grant.extra_value,
			"instance_id": "opponent_%d" % idx,
		})
		idx += 1
	return build_actor(p_catalog, {
		"side": CombatActor.SIDE_ENEMY,
		"display_name": display_name,
		"max_hp": stage_set.max_hp,
		"hp": stage_set.max_hp,
		"items": items,
	})


# ---------------------------------------------------------------------------
# 会话式接口：支持单步、快速计算与表现层驱动
# ---------------------------------------------------------------------------
func begin(p_player: CombatActor, p_enemy: CombatActor, p_battle_id: String, p_rng_scope: String) -> void:
	_player = p_player
	_enemy = p_enemy
	_step = 0
	_finished = false
	_event_seq = 0
	_side_events = [[], []]
	_rng_scope = p_rng_scope
	for a in [_player, _enemy]:
		a.shield = 0.0
		a.burn_stacks.clear()
		a.poison_stacks.clear()
		a.heal_computed = 0.0
		a.heal_actual = 0.0
		a.shield_gained = 0.0
		a.storm_damage = 0.0
		a.damage_attack = 0.0
		a.damage_burn = 0.0
		a.damage_poison = 0.0
		a.damage_taken_shield = 0.0
		a.damage_taken_hp = 0.0
		a.trait_stats.clear()
		a.skill_stats.clear()
		for it in a.items:
			it.cooldown_remaining_ms = it.base_cd_ms
			it.freeze_ms = 0
			it.slow_ms = 0
			it.haste_ms = 0
			it.uses = 0
			it.charge_visual_seq = 0
			it.battle_growth = 0.0
			it.locked_value = 0.0
			it.locked_this_step = false
			it.release_values.clear()
			it.damage_attack = 0.0
			it.damage_burn = 0.0
			it.damage_poison = 0.0
			it.shield_gained = 0.0
			it.heal_computed = 0.0
			it.heal_actual = 0.0

	_result = BattleResult.new()
	_result.battle_id = p_battle_id
	_result.enemy_name = _enemy.display_name
	_result.player_max_hp = _player.max_hp
	_result.enemy_max_hp = _enemy.max_hp


func is_finished() -> bool:
	return _finished


func current_step() -> int:
	return _step


func run_all() -> BattleResult:
	while not _finished:
		step()
	return _result


func step() -> bool:
	if _finished:
		return true
	_step += 1

	# 1. 读取本步已有控制状态，推进自然冷却；冻结者不推进。递减控制时长。
	for actor: CombatActor in [_player, _enemy]:
		for item in actor.items:
			var frozen: bool = item.freeze_ms > 0
			if not frozen:
				var adv: int = item.natural_advance_ms(STEP_MS)
				item.cooldown_remaining_ms = maxi(0, item.cooldown_remaining_ms - adv)
			# 与既有验证脚本一致：控制时长在本步结束时递减
			item.freeze_ms = maxi(0, item.freeze_ms - STEP_MS)
			item.slow_ms = maxi(0, item.slow_ms - STEP_MS)
			item.haste_ms = maxi(0, item.haste_ms - STEP_MS)
			item.locked_this_step = (not frozen) and item.cooldown_remaining_ms <= 0

	# 2. 同轮释放先统一成长再快照，避免装备顺序影响结果。多重释放逐轮累积。
	for actor: CombatActor in [_player, _enemy]:
		for item in actor.items:
			item.release_values.clear()
		for release in range(10):
			var growth := 0.0
			for item in actor.items:
				if item.locked_this_step and release < item.multicast:
					growth += item.weapon_growth_per_use
			for item in actor.items:
				if item.is_weapon(): item.battle_growth += growth
			for item in actor.items:
				if item.locked_this_step and release < item.multicast:
					item.release_values.append(item.base_value + item.battle_growth)
	# 每个自然冷却只重置一次；使用事件读取各次释放快照。
	for actor: CombatActor in [_player, _enemy]:
		for item in actor.items:
			if item.locked_this_step:
				item.cooldown_remaining_ms = item.base_cd_ms
				item.uses += item.multicast
				item.locked_value = item.release_values[0]
				if item.effects.size() > 1:
					for release in item.multicast:
						var target_side := actor.side if item.category in [ItemDef.CAT_SHIELD, ItemDef.CAT_HEAL] else 1 - actor.side
						var release_value := item.release_values[release]
						_emit_and_queue(BattleEvent.TYPE_USE_ITEM, actor.side, item, release_value, release_value, target_side)

	var locked: Array = [locked_items(_player), locked_items(_enemy)]

	# 3. 双方处理本次生命上限变化、护盾和治疗，记录计算治疗量与实际恢复量。
	for i in [CombatActor.SIDE_PLAYER, CombatActor.SIDE_ENEMY]:
		var actor: CombatActor = sides()[i]
		if not is_zero_approx(actor.hp_limit_delta_pending):
			actor.max_hp += actor.hp_limit_delta_pending
			actor.hp = minf(actor.hp, actor.max_hp)
			actor.hp_limit_delta_pending = 0.0
		for item in locked[i]:
			for amount in _effect_values(item, &"shield"):
				actor.shield += amount
				actor.shield_gained += amount
				item.shield_gained += amount
				if item.category == ItemDef.CAT_SHIELD and item.effects.size() <= 1:
					_emit_and_queue(BattleEvent.TYPE_USE_ITEM, i, item, amount, amount, i)
				_emit_and_queue(BattleEvent.TYPE_USE_SHIELD, i, item, amount, amount, i)
			for amount in _effect_values(item, &"heal"):
				var r := _heal(actor, amount, item)
				if item.category == ItemDef.CAT_HEAL and item.effects.size() <= 1:
					_emit_and_queue(BattleEvent.TYPE_USE_ITEM, i, item, amount, amount, i)
				_emit_and_queue(BattleEvent.TYPE_HEAL, i, item, r["computed"], r["actual"], i)

	# 4. Resolve all attack effects before the existing DoT and death phases.
	for i in [CombatActor.SIDE_PLAYER, CombatActor.SIDE_ENEMY]:
		var attacker: CombatActor = sides()[i]
		var target: CombatActor = sides()[1 - i]
		var release_indices := {}
		for item in locked[i]:
			var release_index: int = release_indices.get(item, 0)
			release_indices[item] = release_index + 1
			item.locked_value = item.release_values[release_index]
			for value in _effect_values(item, &"attack"):
				var flat := attacker.weapon_damage_flat if item.is_weapon() else 0.0
				var amount: float = value + flat
				if flat != 0.0:
					attacker.add_trait_stat("weapon_damage_flat", flat)
				_apply_ordinary(target, amount, item, "attack")
				if item.is_weapon():
					if item.effects.size() <= 1:
						_emit_and_queue(BattleEvent.TYPE_USE_ITEM, i, item, amount, amount, 1 - i)
					_emit_and_queue(BattleEvent.TYPE_USE_WEAPON, i, item, amount, amount, 1 - i)

	if _step % DOT_INTERVAL_STEPS == 0:
		for actor: CombatActor in [_player, _enemy]:
			_tick_burn(actor)
			_tick_poison(actor)
	if _step >= STORM_START_STEP and _step % DOT_INTERVAL_STEPS == 0:
		var storm_amount := STORM_BASE_DAMAGE * (1.0 + float(_step - STORM_START_STEP) / 10.0)
		for actor: CombatActor in [_player, _enemy]:
			actor.hp -= storm_amount
			actor.storm_damage += storm_amount
		_result.events.append({
			"event_id": _next_event_id(),
			"step": _step,
			"type": String(BattleEvent.TYPE_STORM),
			"source": "storm",
			"computed": storm_amount,
			"actual": storm_amount,
		})

	# 5. 双方全部伤害完成后检查死亡；同死判玩家失败，不执行后续连锁。
	if not _player.is_alive() or not _enemy.is_alive():
		_same_step_death = (not _player.is_alive()) and (not _enemy.is_alive())
		_outcome = BattleResult.OUTCOME_PLAYER_WIN if (_player.is_alive() and not _enemy.is_alive()) else BattleResult.OUTCOME_PLAYER_LOSE
		_result.events.append({
			"event_id": _next_event_id(),
			"step": _step,
			"type": String(BattleEvent.TYPE_DEATH),
			"source": "",
			"computed": 0.0,
			"actual": 0.0,
			"detail": {"player_hp": maxf(_player.hp, 0.0), "enemy_hp": maxf(_enemy.hp, 0.0), "same_step": _same_step_death},
		})
		_finish()
		return true

	# 6. 存活时施加本次异常与控制，分发使用物品、使用武器、施加灼烧、中毒、治疗等事件。
	for i in [CombatActor.SIDE_PLAYER, CombatActor.SIDE_ENEMY]:
		var actor: CombatActor = sides()[i]
		var target: CombatActor = sides()[1 - i]
		for item in locked[i]:
			for amount in _effect_values(item, &"burn"):
				if item.category == ItemDef.CAT_BURN and item.effects.size() <= 1:
					_emit_and_queue(BattleEvent.TYPE_USE_ITEM, i, item, amount, amount, 1 - i)
				target.add_stack(target.burn_stacks, item.instance_id, amount)
				_emit_and_queue(BattleEvent.TYPE_APPLY_BURN, i, item, amount, amount, 1 - i)
			for amount in _effect_values(item, &"poison"):
				if item.category == ItemDef.CAT_POISON and item.effects.size() <= 1:
					_emit_and_queue(BattleEvent.TYPE_USE_ITEM, i, item, amount, amount, 1 - i)
				target.add_stack(target.poison_stacks, item.instance_id, amount)
				_emit_and_queue(BattleEvent.TYPE_APPLY_POISON, i, item, amount, amount, 1 - i)
			match item.category:
				ItemDef.CAT_HASTE:
					var own_pool: Array[BattleItemState] = []
					for y in actor.items:
						if y.instance_id != item.instance_id:
							own_pool.append(y)
					_apply_control(actor, own_pool, "haste", item.locked_value, i, item)
				ItemDef.CAT_SLOW:
					_apply_control(target, target.items, "slow", item.locked_value, i, item)
				ItemDef.CAT_FREEZE:
					_apply_control(target, target.items, "freeze", item.locked_value, i, item)

		# 7. 独立事件各自触发充能、成长或护盾；被充能到就绪只标记，下一步才允许释放。
		for ev in _side_events[i]:
			if ev.processed:
				continue
			ev.processed = true
			_process_chain_event(actor, target, ev)

	_side_events = [[], []]
	_record_timeline()

	# 计算安全边界：双方均存活则按超时结束（30 秒不是硬性结束时间）
	if _step >= MAX_STEPS:
		_outcome = BattleResult.OUTCOME_TIMEOUT
		_finish()
		return true
	return false


# ---------------------------------------------------------------------------
# 伤害、治疗与状态
# ---------------------------------------------------------------------------

func sides() -> Array:
	return [_player, _enemy]


func _effect_values(item: BattleItemState, kind: StringName) -> Array[float]:
	var result: Array[float] = []
	var primary := &"attack" if item.category == ItemDef.CAT_WEAPON else item.category
	if primary == kind:
		result.append(item.locked_value)
	# Keep legacy single-effect and category behavior; only new secondary effects use own tiers.
	for index in range(1, item.effects.size()):
		var effect := item.effects[index]
		if effect.effect_type == kind:
			result.append(effect.value_at(item.quality, item.locked_value))
	return result


func locked_items(actor: CombatActor) -> Array[BattleItemState]:
	var out: Array[BattleItemState] = []
	for item in actor.items:
		if item.locked_this_step:
			for release in item.multicast:
				out.append(item)
	return out


func _apply_ordinary(target: CombatActor, amount: float, source_item: BattleItemState, kind: String) -> void:
	var used := minf(target.shield, amount)
	target.shield -= used
	var to_hp := amount - used
	target.hp -= to_hp
	target.damage_taken_shield += used
	target.damage_taken_hp += to_hp
	if source_item == null:
		return
	match kind:
		"attack":
			source_item.damage_attack += amount
		"burn":
			source_item.damage_burn += amount
		"poison":
			source_item.damage_poison += amount


func _tick_burn(actor: CombatActor) -> void:
	var total := actor.total_burn()
	if total <= 0.0:
		return
	# 按层数把本次跳伤分摊到各施加来源，避免漏掉被动来源
	var shares: Array[Dictionary] = []
	for s in actor.burn_stacks:
		shares.append({"source": str(s["source"]), "amount": float(s["layers"])})
	var nominal := total
	var used := minf(actor.shield, nominal)
	actor.shield -= used
	var to_hp := nominal - used
	actor.hp -= to_hp
	actor.damage_taken_shield += used
	actor.damage_taken_hp += to_hp
	for sh in shares:
		var sh_item := _find_item(str(sh["source"]))
		if sh_item != null:
			sh_item.damage_burn += float(sh["amount"])
	actor.decay_burn_one_layer()


func _tick_poison(actor: CombatActor) -> void:
	var total := actor.total_poison()
	if total <= 0.0:
		return
	# 中毒绕过护盾，默认不自然衰减
	actor.hp -= total
	actor.damage_taken_hp += total
	for s in actor.poison_stacks:
		var p_item := _find_item(str(s["source"]))
		if p_item != null:
			p_item.damage_poison += float(s["layers"])


func _find_item(instance_id: String) -> BattleItemState:
	for actor: CombatActor in [_player, _enemy]:
		for item in actor.items:
			if item.instance_id == instance_id:
				return item
	return null


func _apply_control(owner: CombatActor, pool: Array, control: String, amount: float, side: int, src: BattleItemState) -> void:
	if pool.is_empty():
		return
	var idx := rng.rand_index_forced(_rng_scope, pool.size())
	var target_item: BattleItemState = pool[idx]
	match control:
		"haste":
			target_item.haste_ms += int(amount)
		"slow":
			target_item.slow_ms += int(amount)
		"freeze":
			target_item.freeze_ms += int(amount)
	_result.events.append({
		"event_id": _next_event_id(),
		"step": _step,
		"type": "apply_control",
		"source": src.instance_id,
		"source_side": side,
		"computed": amount,
		"actual": amount,
		"detail": {"control": control, "target_item": target_item.instance_id, "owner_side": side},
	})


func _heal(actor: CombatActor, amount: float, source_item: BattleItemState) -> Dictionary:
	var computed := amount + actor.heal_computed_flat
	if actor.heal_computed_flat != 0.0:
		actor.add_trait_stat("heal_computed_flat", actor.heal_computed_flat)
	actor.heal_computed += computed
	var actual := minf(computed, actor.max_hp - actor.hp)
	if actual < 0.0:
		actual = 0.0
	actor.hp += actual
	actor.heal_actual += actual
	if source_item != null:
		source_item.heal_computed += computed
		source_item.heal_actual += actual
	var side := actor.side
	_result.events.append({
		"event_id": _next_event_id(),
		"step": _step,
		"type": String(BattleEvent.TYPE_HEAL),
		"source": source_item.instance_id if source_item != null else "trait",
		"source_side": side,
		"computed": computed,
		"actual": actual,
		"detail": {"full_hp_still_event": actual <= 0.0},
	})
	return {"computed": computed, "actual": actual}


func _emit_and_queue(type_: StringName, side: int, item: BattleItemState, computed: float, actual: float, target_side: int) -> void:
	var ev := BattleEvent.new()
	ev.event_id = _next_event_id()
	ev.step = _step
	ev.type = type_
	ev.source_instance_id = item.instance_id
	ev.source_side = side
	ev.target_side = target_side
	ev.computed = computed
	ev.actual = actual
	_result.events.append(ev.to_dict())
	_side_events[side].append(ev)


func _next_event_id() -> String:
	_event_seq += 1
	return "e%d" % _event_seq


# ---------------------------------------------------------------------------
# 连锁事件处理
# ---------------------------------------------------------------------------

func _process_chain_event(actor: CombatActor, target: CombatActor, ev: BattleEvent) -> void:
	match ev.type:
		BattleEvent.TYPE_USE_WEAPON:
			# 护身佩自身被动：当使用武器时，充能此物品 1 秒（每件各自响应）
			for y in actor.items:
				if y.self_passive == ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE:
					y.cooldown_remaining_ms = maxi(0, y.cooldown_remaining_ms - CHARGE_MS)
					y.charge_visual_seq += 1
			# 吸血：伤害后、存活时的连锁阶段治疗，不能复活已死亡角色
			if actor.heal_on_weapon_use > 0.0:
				var r := _heal(actor, actor.heal_on_weapon_use, null)
				actor.add_trait_stat("heal_on_weapon_use", r["computed"])
				_apply_recovery_skill(actor, "weapon_use")
		BattleEvent.TYPE_USE_SHIELD:
			var lvl := actor.skill_level(&"ever_stronger")
			if lvl >= 0:
				var def := catalog.skill(&"ever_stronger")
				var amount := def.value_at(lvl)
				for y in actor.items:
					if y.is_weapon():
						y.battle_growth += amount
				actor.add_skill_stat("ever_stronger", amount)
		BattleEvent.TYPE_APPLY_BURN:
			var lvl := actor.skill_level(&"flame_aegis")
			if lvl >= 0:
				var def := catalog.skill(&"flame_aegis")
				var amount := def.value_at(lvl)
				actor.shield += amount
				actor.shield_gained += amount
				actor.add_skill_stat("flame_aegis", amount)
		BattleEvent.TYPE_HEAL:
			_apply_recovery_skill(actor, "heal_event")
		_:
			pass


## 回春护体：治疗事件后获得护盾，满血也触发。获得护盾不是使用护盾物品，不递归触发越战越勇。
func _apply_recovery_skill(actor: CombatActor, _reason: String) -> void:
	var lvl := actor.skill_level(&"rejuvenating_aegis")
	if lvl < 0:
		return
	var def := catalog.skill(&"rejuvenating_aegis")
	var amount := def.value_at(lvl)
	actor.shield += amount
	actor.shield_gained += amount
	actor.add_skill_stat("rejuvenating_aegis", amount)


# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------

func _record_timeline() -> void:
	if _step % TIMELINE_EVERY_STEPS != 0:
		return
	_result.timeline.append({
		"step": _step,
		"player_hp": maxf(_player.hp, 0.0),
		"player_shield": maxf(_player.shield, 0.0),
		"player_burn": _player.total_burn(),
		"player_poison": _player.total_poison(),
		"enemy_hp": maxf(_enemy.hp, 0.0),
		"enemy_shield": maxf(_enemy.shield, 0.0),
		"enemy_burn": _enemy.total_burn(),
		"enemy_poison": _enemy.total_poison(),
		"player_cd": _cooldowns(_player),
		"enemy_cd": _cooldowns(_enemy),
	})


func _cooldowns(actor: CombatActor) -> Array:
	var out := []
	for item in actor.items:
		out.append([
			String(item.definition_id),
			item.cooldown_remaining_ms,
			item.base_cd_ms,
			item.freeze_ms,
			item.slow_ms,
			item.haste_ms,
		])
	return out


func _finish() -> void:
	_finished = true
	_record_timeline()
	_result.outcome = _outcome
	_result.steps = _step
	_result.time_seconds = float(_step) * STEP_SECONDS
	_result.same_step_death = _same_step_death
	_result.player_hp = maxf(_player.hp, 0.0)
	_result.player_shield = maxf(_player.shield, 0.0)
	_result.player_max_hp = _player.max_hp
	_result.enemy_hp = maxf(_enemy.hp, 0.0)
	_result.enemy_shield = maxf(_enemy.shield, 0.0)
	_result.enemy_max_hp = _enemy.max_hp
	_result.enemy_name = _enemy.display_name
	if _step >= MAX_STEPS and _player.is_alive() and _enemy.is_alive():
		_result.outcome = BattleResult.OUTCOME_TIMEOUT
	_result.player_stats = _actor_stats(_player)
	_result.enemy_stats = _actor_stats(_enemy)
	_result.item_stats = {
		"player": _item_stats_array(_player),
		"enemy": _item_stats_array(_enemy),
	}


func result() -> BattleResult:
	return _result


## 只读访问双方运行状态（供表现层显示血条、冷却与日志，不修改任何战斗数据）
func player_actor() -> CombatActor:
	return _player


func enemy_actor() -> CombatActor:
	return _enemy


func _actor_stats(actor: CombatActor) -> Dictionary:
	return {
		"hp": maxf(actor.hp, 0.0),
		"max_hp": actor.max_hp,
		"shield": maxf(actor.shield, 0.0),
		"shield_gained": actor.shield_gained,
		"heal_computed": actor.heal_computed,
		"heal_actual": actor.heal_actual,
		"storm_damage": actor.storm_damage,
		"damage_taken_shield": actor.damage_taken_shield,
		"damage_taken_hp": actor.damage_taken_hp,
		"burn_at_end": actor.total_burn(),
		"poison_at_end": actor.total_poison(),
		"trait_stats": actor.trait_stats.duplicate(),
		"skill_stats": actor.skill_stats.duplicate(),
	}


func _item_stats_array(actor: CombatActor) -> Array:
	var out := []
	for item in actor.items:
		out.append(item.stats_summary())
	return out
