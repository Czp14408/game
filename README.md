# 游戏工程文档索引

本页是全工程文档总入口；新增、迁移和归档按[文档存放规范](DOCUMENTATION.md)执行。可编辑工程在[godot_prototype/](godot_prototype/)，物品内容入口在[content/README.md](content/README.md)。

## 当前设计

| 文档 | 职责 |
| --- | --- |
| [核心规则定稿](docs/design/游戏核心规则定稿.md) | 公共规则的唯一设计依据 |
| [世界与内容设计](docs/design/世界与内容设计.md) | 主题装备、技能、成长与测试参数 |
| [第一阶段设计方案](docs/design/第一阶段设计方案.md) | 新版主线、节点牌面与路线样本 |
| [物品制作指南](docs/design/item-system.md) | 已实现的Excel编辑、生成、渠道与展示契约 |

规则确认、模型验证、工程接入和人工验收是不同状态。工程已有新版武道节点测试入口，尚未交付完整新版第一阶段。

## 工程与制作

- [工程复用与实现边界](docs/engineering/engineering-status.md)：现有模块、适配风险与文档核查。
- [物品系统交付状态](docs/status/item-system-status.md)：按核对日期记录完成范围与待办。
- [UI修改工作流](docs/guides/ui修改迭代工作流.md)：素材生成、布局访问与验证工序。
- [UI组件说明](docs/design/ui/)：战斗、共用面板与按钮素材，按各文档注明的版本使用。
- [新版节点首批接入](docs/validation/新版节点首批接入-2026-10-14.md)：当前开发测试入口的真实范围。

## 验证与参考

- [验证与人工验收](docs/validation/)：执行范围、输入、结果与未执行项。
- [本轮文档归档与提交前验证](docs/validation/文档归档与提交前验证-2026-10-15.md)：迁移范围与实际重跑结果。
- [研究资料](docs/research/)：外部机制与案例，不自动成为本作规则。
- [早期原型资料](docs/history/early-prototype/)：旧玩法、UI需求、技术方案、固定数值基线与路线图。
- [2026-10-14固定推演](docs/history/2026-10-14固定推演/)：历史主题配置与账本。
- [历史架构评估](docs/history/architecture-review-2026-10-08.md)：原日期代码与测试记录。
- [验证脚本与原始证据](_验证/)：模型脚本、结果、复演账本与截图，不是运行时模块。

## 协作

- [AGENTS.md](AGENTS.md)：工程协作指引。
- [工单规则](docs/agents/issue-tracker.md)、[标签规范](docs/agents/triage-labels.md)、[领域文档约定](docs/agents/domain.md)。
- GitHub Issues维护需求与待办；历史文档中的工单状态不是实时状态。
