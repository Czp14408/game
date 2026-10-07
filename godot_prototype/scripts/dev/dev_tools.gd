class_name DevTools
extends Node
## 开发测试入口的总开关与三路线回放的显式固定输入。
## 边界：测试入口只放开发菜单或调试构建；正常游玩不读取这里的任何数据。
## 依据：游戏可玩原型技术方案.md 第 14 节。
##
## 说明：本类只使用静态状态，不注册为 autoload。
## 这样普通运行、编辑器调试与 --script 无画面测试使用同一份开关，
## 避免自动加载单例在无画面脚本模式下不可见的问题。

const MODE_RANDOM := &"random_play"
const MODE_REPLAY_NORMAL := &"replay_normal"
const MODE_REPLAY_LOW := &"replay_low"
const MODE_REPLAY_FAILURE := &"replay_failure"
const MODE_BATTLE_LAB := &"battle_lab"

## 阶段集合定义 ID（回放使用第一阶段）
const STAGE_ID := &"stage_01"

static var dev_enabled: bool = true
static var mode: StringName = MODE_RANDOM
static var world_seed: int = 20261007


static func is_replay() -> bool:
	return mode in [MODE_REPLAY_NORMAL, MODE_REPLAY_LOW, MODE_REPLAY_FAILURE]


static func mode_name() -> String:
	match mode:
		MODE_REPLAY_NORMAL:
			return "三路线回放：正常成长"
		MODE_REPLAY_LOW:
			return "三路线回放：掉落不佳"
		MODE_REPLAY_FAILURE:
			return "三路线回放：连续战败"
		MODE_BATTLE_LAB:
			return "战斗实验室"
		_:
			return "随机游玩"


## 三路线回放的固定掉落序列：节点 → "material" / 物品 definition_id
static func drop_override() -> Dictionary:
	match mode:
		MODE_REPLAY_NORMAL:
			return {
				"02": "bandit_knife", "05": "material", "08": "ward_charm",
				"12": "long_blade", "15": "heavy_hammer",
			}
		MODE_REPLAY_LOW, MODE_REPLAY_FAILURE:
			return {
				"02": "material", "05": "material", "08": "material",
				"12": "material", "15": "material",
			}
	return {}


## 三路线回放的阶段对手（文档样本为“持续伤害＋治疗”）
static func stage_override() -> Dictionary:
	if is_replay():
		return {"template": &"damage_over_time", "extra": &"rejuvenator"}
	return {}


## 三路线回放的固定验证库存（明确测试输入，不代表随机池）
static func fixed_shops() -> Dictionary:
	if not is_replay():
		return {}
	return {
		"03/gear_shop": {"items": ["ward_charm", "short_blade", "rejuvenator", "fire_oil"], "skills": []},
		"03/clinic": {"items": ["recovery_draught", "rejuvenator"], "skills": []},
		"03/weapon_shop": {"items": [], "skills": []},
		"__deity__/deity_mixed": {"items": ["short_blade", "rejuvenator", "poison_needle"], "skills": ["ever_stronger"]},
	}
