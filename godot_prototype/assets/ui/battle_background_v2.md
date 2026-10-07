# 战斗背景 v2

使用内置 imagegen 编辑 v1，2026-10-07。PNG 不透明背景，尚未接入场景。

布局：上方敌人、下方玩家；双方左侧预留头像、名字及状态面板；中间各有技能区、独立细长生命槽和连续战斗栏；中央分隔区用于计时；右侧用于操作与日志。十格划分、头像、生命填充、状态和文字由 Godot 动态叠加。

上下区域的具体尺寸和像素缩放需接入工程时验证。

## 最终生成描述

Edit the empty pixel-art background to reserve portrait, status, skill and health slots for both sides. Preserve wood/bronze frames, charcoal panels and right operations sidebar. Each half: left square portrait socket, name plaque, status area; to the right a wide skill strip, clearly separate thin recessed empty health trough, and continuous combat tray for ten dynamically drawn slots. Keep upper/lower tray widths equal and central timer divider. Remove all actual content, symbols, labels, grid lines, buttons and scenery. Functional aligned modular panels with restrained borders; no health fill or baked icons.
