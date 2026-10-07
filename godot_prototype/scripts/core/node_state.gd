class_name NodeState
extends RefCounted
## 节点状态：收费结算、敌人/容器/事件状态、商店库存、离开位置。
## 场景销毁后按本对象重建，重访不刷新已领取资源。

var node_id: String = ""
var entered: bool = false
var fee_paid: bool = false
var fee_amount: int = 0
var discovered: bool = false
var saved_position: Vector2 = Vector2.ZERO
var encounters: Dictionary = {}    # encounter_key -> EncounterState
var shops: Dictionary = {}         # shop_id -> ShopState
var containers: Dictionary = {}    # container_key -> {"opened": bool, "table": StringName, "drops": Array}
var events_done: Dictionary = {}   # event_id -> true
## 已显示原因的守路连接：连接键 -> true
var guard_revealed: Dictionary = {}


func encounter(key: String) -> EncounterState:
	return encounters.get(key)


func shop(shop_id: StringName) -> ShopState:
	return shops.get(shop_id)
