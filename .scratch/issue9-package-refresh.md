## 试玩包刷新（提交 `50a050c`）

便携包 `dist/wudao_prototype/` 已就地同步到最新工程，包内复测 **646 项无画面断言全通过**。

包内变化：

- 新增 `run_evidence.bat`：在包内重新生成三份 R0 证据（复演账本／构筑方向样本／背包容量压力），产物落在 `evidence/`。
- 包内附带 `R0收尾证据.md`（与 `人工验收清单.md`、`游戏原型已知问题清单.md` 并列）。
- `README.md` 的断言数量由陈旧的 635 更正为 646，并补充证据说明。
- `package_windows.sh` 增加健壮性处理：引擎运行程序内容一致时跳过覆盖；
  覆盖被拒（Device or resource busy）时不再中断整次打包，改为警告后继续。
  本次即因该问题导致前两次打包在中途停止、bat 与文档未更新，现已修复。

**仍缺**：标准单文件导出需要同版本导出模板
（`%APPDATA%\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe`，约 1.28 GB，
实测下载速率 37–78 KB/s，不具备等待条件）。按计划 §4「等待期间使用已验证的便携包进行内部玩法迭代」处理。
装好模板后运行 `export_release.bat` 即可产出标准 exe。
