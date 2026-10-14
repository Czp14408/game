# 工程复用与文档核查

核对日期：2026-10-15。依据：当前工作区源码（包含原有未提交改动）、设计文档和已存验证记录。此处复用核查只修改文档，未在核查时运行游戏回归、人工试玩或查询GitHub工单状态。后续目录整理与提交前重跑另见[归档验证记录](../validation/文档归档与提交前验证-2026-10-15.md)。

## 当前实现边界

- 公共规则以[核心规则](../design/游戏核心规则定稿.md)为准，主题参数与阶段牌面分别维护在[内容设计](../design/世界与内容设计.md)和[阶段设计](../design/第一阶段设计方案.md)。设计确认不等于工程交付。
- `AppRoot.register_pages()`按`RunState.card_exploration`选择`PageNodeCards`或`PageMinimap`。新版开发入口与旧自由移动入口并存，不应全局替换旧费用与复演输入。
- `WorldService.entry_fee/can_travel/travel`已有模式分支：新模式消耗探索时间，旧模式扣货币；免费入口与重访共用。新版入口预算11，但仍使用旧武道内容。
- `NodeCardService`已提供顶层可接触、有限承接和摆放保留。危险放置、实物暂存、未发现牌揭示、完整新主线与赛博世界不据此视为实现。详细边界维护在[首批接入记录](../validation/新版节点首批接入-2026-10-14.md)，不在本页复制测试统计。

## 可以复用的模块

以下是现有实现的复用判断，不是对全部新规则兼容性的测试证明。路径均相对于`godot_prototype/`。

| 模块与入口 | 已有能力 | 新版接入边界 |
| --- | --- | --- |
| `scripts/combat/combat_engine.gd`及`combat_actor/battle_item_state/battle_event/battle_result.gd` | 固定步长、脱离页面的自动战斗，状态、事件与结果分层 | 保留引擎，逐项补新效果与来源统计；不能认为主题模型脚本已进入引擎 |
| `scripts/data/`、`scripts/core/content_catalog.gd`与`item_instance.gd` | 共享定义与试炼实例分离，稳定ID加载和内容校验 | 沿用类型与ID；新内容需真正生成并被目录加载，不复制模型中的物品数值 |
| `tools/import_items.py`、`item_special.py`、`item_channels.py`、`item_import_report.py` | Excel校验、模板展开、物品与渠道生成、报告 | 继续使用`content/items.xlsx`为物品唯一编辑来源；新增机制先补运行时与导入契约 |
| `tools/normalize_item_image.py`、`art_palette.py`、`archive_items.py` | 图片规范化、色表检查、内容留档 | 可继续用于新物品；归档不是游戏存档，图片工具不是物品配置GUI |
| `scripts/economy/inventory_service.gd` | 装备、卸下、占格、重排、自动合成与恢复品 | 保留业务服务；合成预览及失败实例副作用需收紧后再扩大接入 |
| `scripts/economy/economy_service.gd`、`shop_service.gd`与`price_table.gd` | 购买、指定位置购买、出售、刷新、锁定与账本 | 复用交易流程；新经济、支付来源与强化消费另行适配，旧价格不是新参数 |
| `scripts/world/encounter_service.gd`、`quest_service.gd` | 遭遇持久状态、战斗提交、防重复结算、任务与奖励 | 复用状态与奖励流程；新事件主线、任务物和牌面触发条件不沿用旧击杀条件冒充实现 |
| `scripts/world/world_service.gd`与`node_card_service.gd` | 图连接、守路、重访、回归限制、新模式时间分支、叠牌基础 | 扩展现有服务；`NodeCardService.specs()`目前从旧节点定义翻译对象，不是新阶段牌面库 |
| `scripts/core/random_service.gd`与`session_recorder.gd` | 作用域随机流、抽取记录、事件与耗时记录 | 复用复现与诊断能力；仅保证同版本复现，不能要求同种子与JS模型相同，日志不是可恢复存档 |
| `scripts/ui/item_card.gd`及`item_card_layout/item_skin/item_stat_badge/item_multicast_badge/item_motion.gd` | 卡面、品质、说明、数值与冷却状态展示 | 优先用于物品牌；不要把人物、敌人、任务牌强行当成物品实例 |
| `scripts/ui/panel_inventory.gd`及`inventory_skin/battle_skin/system_skin/ui_kit.gd` | 清单驱动物品面板、素材与布局访问、通用控件 | 可保留卡面和皮肤；旧停靠位置、键位及自由移动HUD不直接搬到新版 |
| `tests/headless_main.gd`、各业务测试与`node_cards_entry_test.gd` | 既有规则回归、内容和页面构建、新节点入口专项断言 | 保留旧模式回归，逐项增加新模式覆盖；旧通过数字和固定复演不替代新版完整验收 |

## 不宜直接搬用的部分

1. `PageMinimap`的房间、角色移动、附近设施和拖拽状态机耦合在页面内。可参考输入处理，不复制整个页面，也不把自由移动作为新探索的前提。
2. `RunController.preview_auto_synth()`仍调用`state.new_instance()`；`InventoryService.synthesize/auto_synthesize_into()`存在先登记产物再做容量检查的路径。复用前应统一预览与提交计算，并补实例集合/序号不变的失败断言。
3. `PageBattle`仍直接移除`pending_drops`，`PageMinimap`仍调用`InventoryService._insert_at()`。新增领取或拖拽入口应先收拢成业务命令，避免再复制一套资格和容量判断。
4. `PagePreBattle/PagePostBattle/PageStagePreview`仍注册，但已有统一战斗页流程。页面仍存在不代表需要照搬旧多页交互。
5. `_验证/*.mjs`与旧复演账本是模型、样本和证据。它们可帮助构造测试输入，但不是Godot业务模块；不要整段移植其中的战斗或经济算法形成第二份规则。

建议接入顺序：保留战斗、物品、交易和测试基础 → 收紧预览/领取接口 → 扩展节点牌与新任务 → 接入主题内容和新经济 → 验证完整第一阶段。无需推倒重建，也不在本轮文档清理中顺手改玩法代码。

## 文档清理结果

- 修正索引、核心规则及两份当前内容设计中“不进行工程接入”的全局描述，明确首批入口已存在而完整新设计未实现。
- 给早期玩法、旧原型需求/经济方案、主界面与UI组件说明、迭代计划加适用边界，避免自由移动、金币收费和旧技能限制被误用为当前规格。
- 将旧问题清单、人工勾选、架构评估和物品状态中的数量、键位、测试统计限定为原日期证据；不改写已执行结果，不声称本轮已重新通过。
- 保留历史推演、数值研究、验证脚本、截图和归档。已有`docs/history/2026-10-14固定推演/README.md`明确历史范围，未重复移动或删除这些输入。
- 未删除业务模块、未改生成资源、未刷新工单状态。后续能力变化应更新实际负责该范围的文档，不在多个专题复制一份“最新进度”。
- 检查57份Markdown的相对文件链接，发现按钮组件说明的三张历史参考图缺失；移除失效链接并明确标注缺失，没有用其他图片冒充原图。修复后相对文件链接检查与`git diff --check`通过。
