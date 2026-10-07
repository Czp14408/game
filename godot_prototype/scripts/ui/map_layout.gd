class_name MapLayout
extends RefCounted
## 18 节点样本地图的展示坐标与区域分组。
## 边界：只负责界面摆放，不参与任何规则计算（费用、连接、守路仍由 WorldService 判定）。
## 依据：游戏单局推演.md 第 3 节 18 节点样本连接；tools/build_content.gd 连接表。

## 归一化坐标（0—1），绘制时按画布尺寸放大
static var POSITIONS := {
	"01": Vector2(0.10, 0.24),
	"02": Vector2(0.23, 0.12),
	"03": Vector2(0.25, 0.34),
	"04": Vector2(0.37, 0.08),
	"17": Vector2(0.36, 0.38),
	"18": Vector2(0.47, 0.48),
	"05": Vector2(0.36, 0.54),
	"06": Vector2(0.47, 0.42),
	"07": Vector2(0.48, 0.16),
	"08": Vector2(0.58, 0.28),
	"09": Vector2(0.44, 0.68),
	"10": Vector2(0.56, 0.78),
	"11": Vector2(0.68, 0.20),
	"12": Vector2(0.76, 0.31),
	"13": Vector2(0.68, 0.49),
	"14": Vector2(0.80, 0.62),
	"15": Vector2(0.89, 0.45),
	"16": Vector2(0.89, 0.22),
}

static var AREAS := {
	"town": ["01", "02", "03", "04", "06", "07", "17", "18"],
	"road": ["05", "08", "09", "10"],
	"camp": ["11", "12", "13", "14", "15", "16"],
}

static var AREA_NAMES := {"town": "城镇", "road": "野外", "camp": "土匪据点"}


static func position_of(node_id: String) -> Vector2:
	return POSITIONS.get(node_id, Vector2(0.5, 0.5))


static func area_of(node_id: String) -> String:
	for key in AREAS.keys():
		if (AREAS[key] as Array).has(node_id):
			return key
	return ""


static func area_name(node_id: String) -> String:
	return AREA_NAMES.get(area_of(node_id), "未知")
