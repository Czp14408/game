class_name ShopState
extends RefCounted
## 商店实例状态：商品实例、购买空位、锁定、刷新序号。
## 同一节点多家店各自独立库存，分别付费刷新。

class Slot:
	var is_skill: bool = false
	var item: ItemInstance = null      # 物品商品
	var skill_id: StringName = &""     # 技能商品
	var quality: int = 0
	var purchased: bool = false

var shop_key: String = ""     # 实例键：node_id/shop_id
var shop_id: StringName = &""
var slots: Array = []         # Array[Slot]
var locked: bool = false
var refresh_serial: int = 0
var initialized: bool = false


func available_slots() -> Array:
	var out: Array = []
	for s in slots:
		if not (s as Slot).purchased:
			out.append(s)
	return out


func empty_slot_count() -> int:
	return available_slots().size()
