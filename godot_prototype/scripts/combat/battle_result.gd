class_name BattleResult
extends RefCounted
## 一场战斗的结算结果。只把有效当前生命与结算结果提交回试炼。

const OUTCOME_PLAYER_WIN := &"player_win"
const OUTCOME_PLAYER_LOSE := &"player_lose"
const OUTCOME_TIMEOUT := &"timeout"

var battle_id: String = ""
var outcome: StringName = OUTCOME_TIMEOUT
var time_seconds: float = 0.0
var steps: int = 0
var same_step_death: bool = false

var player_hp: float = 0.0
var player_max_hp: float = 0.0
var player_shield: float = 0.0
var enemy_hp: float = 0.0
var enemy_max_hp: float = 0.0
var enemy_shield: float = 0.0
var enemy_name: String = ""

var player_stats: Dictionary = {}
var enemy_stats: Dictionary = {}
var item_stats: Dictionary = {}      # "player"/"enemy" -> Array[Dictionary]
var events: Array[Dictionary] = []
var timeline: Array[Dictionary] = []


func winner_is_player() -> bool:
	return outcome == OUTCOME_PLAYER_WIN


func outcome_text() -> String:
	match outcome:
		OUTCOME_PLAYER_WIN:
			return "胜利"
		OUTCOME_PLAYER_LOSE:
			return "战败"
		_:
			return "超时未分胜负"


func duration_text() -> String:
	return "%.1f 秒" % time_seconds


## 首屏反馈：胜负、耗时、双方剩余生命、双方各物品的释放次数/伤害/护盾/实际治疗量
func headline() -> Dictionary:
	return {
		"outcome": outcome_text(),
		"time": duration_text(),
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"enemy_hp": enemy_hp,
		"enemy_max_hp": enemy_max_hp,
		"enemy": enemy_name,
	}
