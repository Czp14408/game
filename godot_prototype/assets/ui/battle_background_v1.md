# 战斗界面背景 v1

生成方式：内置 imagegen，2026-10-07。参考本次确认的战斗界面原型进行编辑。

用途：不透明 PNG 静态背景。上方敌方信息与战斗栏，下方玩家战斗栏与信息，右侧操作区。尚未绑定现有场景；实际缩放、控件位置和像素清晰度需接入后验证。

十格战斗栏、人物、物品、技能、生命、冷却、文字和操作按钮由 Godot 控件独立叠加；背景不包含固定格线，以支持不同物品占格。

## 最终生成描述

Edit the confirmed battle UI into an empty reusable Godot background. Preserve landscape composition, crisp retro pixel art, warm wood and bronze frames, charcoal inset surfaces, upper enemy region, lower player region, and a right sidebar about 20% width. Remove characters, portraits, item artwork, skill icons, health fills, cooldown meters, all numbers, text, timers, logs, buttons, and slot badges. Remove banners, torches, lanterns, foliage, rubble, mountains and thematic clutter. Keep only aligned empty panels: upper information strip, upper combat tray, center divider, lower combat tray, lower information strip, and right sidebar with subtle separators. Combat trays are continuous empty surfaces without item borders or grid lines; Godot draws the ten-slot grids dynamically. Use restrained pixel shading, low-contrast textures, no symbols or watermark.
