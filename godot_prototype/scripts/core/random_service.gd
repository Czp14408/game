class_name RandomService
extends RefCounted
## 独立随机流：世界内容、每个商店、掉落、阶段模板、每场战斗各自一条流。
## 边界：查看界面不消耗随机数；记录主种子、作用域与关键抽取结果。
## 依据：游戏可玩原型技术方案.md 第 8 节。
##
## 注意：Godot 与既有 JavaScript 验证脚本的随机算法不同，不能要求相同整数种子下结果一致。
## 本服务只保证同版本内可复现（seed/state）与作用域互不干扰。

var master_seed: int = 0
var _streams: Dictionary = {}   # String -> RandomNumberGenerator
var _counters: Dictionary = {}  # String -> int
var draw_log: Array[Dictionary] = []
var log_enabled: bool = true

const MAX_LOG_ENTRIES := 20000


static func create(p_master_seed: int) -> RandomService:
	var s := RandomService.new()
	s.master_seed = p_master_seed
	return s


func stream(scope: String) -> RandomNumberGenerator:
	if _streams.has(scope):
		return _streams[scope]
	var rng := RandomNumberGenerator.new()
	rng.seed = _derive_seed(scope)
	_streams[scope] = rng
	_counters[scope] = 0
	return rng


func _derive_seed(scope: String) -> int:
	# 作用域散列与主种子组合，保证各流互不干扰且同种子可复现
	var h := hash("%s|%d" % [scope, master_seed])
	if h == 0:
		h = 1
	return h


func count(scope: String) -> int:
	return _counters.get(scope, 0)


func _record(scope: String, kind: String, detail: Variant) -> void:
	var idx: int = _counters.get(scope, 0)
	_counters[scope] = idx + 1
	if not log_enabled or draw_log.size() >= MAX_LOG_ENTRIES:
		return
	draw_log.append({
		"scope": scope,
		"index": idx,
		"kind": kind,
		"detail": detail,
		"master_seed": str(master_seed),
	})


## 抽取下标 [0, n)
func rand_index(scope: String, n: int) -> int:
	if n <= 0:
		return -1
	var rng := stream(scope)
	var v := rng.randi_range(0, n - 1)
	_record(scope, "index", {"n": n, "value": v})
	return v


func rand_float(scope: String) -> float:
	var rng := stream(scope)
	var v := rng.randf()
	_record(scope, "float", v)
	return v


func pick(scope: String, pool: Array) -> Variant:
	var i := rand_index(scope, pool.size())
	return null if i < 0 else pool[i]


## 按权重抽取下标；权重和不必为 1
func pick_weighted(scope: String, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return -1
	var roll := rand_float(scope) * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if roll < acc:
			_record(scope, "weighted", {"index": i, "roll": roll})
			return i
	return weights.size() - 1


## 战斗内抽取：显式目标序列支持精确对照回放
var forced_index_sequence: Dictionary = {}  # scope -> {seq_index: value}
func rand_index_forced(scope: String, n: int) -> int:
	if forced_index_sequence.has(scope):
		var c: int = _counters.get(scope, 0)
		var seq: Dictionary = forced_index_sequence[scope]
		if seq.has(c):
			_counters[scope] = c + 1
			var v: int = int(seq[c])
			_record(scope, "forced_index", {"n": n, "value": v})
			return clampi(v, 0, n - 1)
	return rand_index(scope, n)


func state_snapshot() -> Dictionary:
	var out := {}
	for k in _streams.keys():
		out[k] = {
			"seed": str((_streams[k] as RandomNumberGenerator).seed),
			"state": str((_streams[k] as RandomNumberGenerator).state),
			"count": _counters.get(k, 0),
		}
	return out
