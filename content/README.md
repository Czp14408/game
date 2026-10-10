# 物品内容入口

正式配置：`items.xlsx`。全部物品在这里维护，生成资源不手改。

- [物品系统设计与制作指南](../docs/design/item-system.md)：字段、机制、渠道、卡面、素材、动效和完整操作步骤。
- [最新状态与进度](../docs/item-system-status.md)：已完成、验证结果、版本、备份和待办。

日常入口依次为 `normalize_item_image.cmd` → `items.xlsx` → `check_items.cmd` → `update_items.cmd` → `view_item_report.cmd` → `preview_items.cmd` → `archive_items.cmd`。保存关闭 Excel 后更新；只校验不代表已应用。
