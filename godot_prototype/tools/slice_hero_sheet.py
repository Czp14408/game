#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 5x5 主角动作表切成独立 PNG（去白底 + 自动裁剪 + 统一画布）。

用法:
  python tools/slice_hero_sheet.py <源图> <输出目录> [--grid 5] [--cells]

约定:
- 源图必须是规整 NxN 网格、纯白底，角色在格内底对齐。
- 去底用「四边洪水填充」，只吃与画布边缘连通的白色，被深色衣物包围的白衬衫会被保留。
- 对紧贴背景的抗锯齿像素做减边（de-fringe）：按白度给部分 alpha，并反预乘颜色，避免暗底上出现白描边。
- 产物：
    trimmed/       紧贴角色的最小外接矩形，默认产出，供头像与立绘直接取用
    manifest.json  每格的行列、原格坐标与裁剪框，供引擎侧按需生成 AtlasTexture
    _contact.png   带行列编号的联系表，便于人工指认姿势
    cells/         统一画布切片，保留原始格位与基线；仅在传入 --cells 时产出（动画对齐用）
"""

import json
import math
import sys
import os
from collections import deque

from PIL import Image, ImageDraw
import numpy as np

WHITE_THRESHOLD = 238      # 判定「接近白」的下限（min(R,G,B)）
FRINGE_THRESHOLD = 200     # 进入减边处理的阈值（稍宽，覆盖抗锯齿带）


def flood_background(rgb: np.ndarray, thr: int = WHITE_THRESHOLD) -> np.ndarray:
    """从四边洪水填充，返回「确定是背景」的布尔掩码。"""
    h, w, _ = rgb.shape
    near_white = rgb.min(axis=2) > thr
    bg = np.zeros((h, w), dtype=bool)
    queue = deque()

    def push(y: int, x: int) -> None:
        if near_white[y, x] and not bg[y, x]:
            bg[y, x] = True
            queue.append((y, x))

    for x in range(w):
        push(0, x)
        push(h - 1, x)
    for y in range(h):
        push(y, 0)
        push(y, w - 1)

    while queue:
        y, x = queue.popleft()
        if y > 0:
            push(y - 1, x)
        if y < h - 1:
            push(y + 1, x)
        if x > 0:
            push(y, x - 1)
        if x < w - 1:
            push(y, x + 1)
    return bg


def drop_specks(bg: np.ndarray, min_area: int = 48) -> np.ndarray:
    """把「非背景但极小」的孤立块并回背景（JPEG 噪点会制造这类白底斑点）。"""
    h, w = bg.shape
    content = ~bg
    seen = np.zeros((h, w), dtype=bool)
    out = bg.copy()
    for sy in range(h):
        for sx in range(w):
            if not content[sy, sx] or seen[sy, sx]:
                continue
            queue = deque([(sy, sx)])
            seen[sy, sx] = True
            comp = []
            while queue:
                y, x = queue.popleft()
                comp.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and content[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if len(comp) < min_area:
                for y, x in comp:
                    out[y, x] = True
    return out


def to_rgba(rgb: np.ndarray) -> np.ndarray:
    """去底 + 减边，返回 RGBA。"""
    h, w, _ = rgb.shape
    bg = drop_specks(flood_background(rgb))

    # 与背景相邻、但本身在抗锯齿带里的像素，按白度给部分 alpha
    dilated = np.zeros_like(bg)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        shifted = np.roll(np.roll(bg, dy, axis=0), dx, axis=1)
        dilated |= shifted
    ring = dilated & ~bg

    alpha = np.full((h, w), 255.0)
    alpha[bg] = 0.0

    minch = rgb.min(axis=2).astype(np.float64)
    # 环上像素：白度越高越透明
    span = float(FRINGE_THRESHOLD - 150)
    fac = np.clip((minch - 150.0) / span, 0.0, 1.0)
    alpha[ring] = 255.0 * (1.0 - fac[ring])

    a = (alpha / 255.0)[..., None]
    color = rgb.astype(np.float64)
    safe = np.maximum(a, 1e-6)
    # 反预乘：假设原像素 = 真色*a + 白*(1-a)
    unpre = (color - 255.0 * (1.0 - a)) / safe
    unpre = np.clip(unpre, 0, 255)
    out = np.dstack([unpre, alpha]).astype(np.uint8)
    return out


def bbox_of_alpha(rgba: np.ndarray, thr: int = 8):
    mask = rgba[:, :, 3] > thr
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, outdir = sys.argv[1], sys.argv[2]
    grid = 5
    if "--grid" in sys.argv:
        grid = int(sys.argv[sys.argv.index("--grid") + 1])
    want_cells = "--cells" in sys.argv

    img = Image.open(src).convert("RGB")
    W, H = img.size
    rgba = to_rgba(np.asarray(img))

    os.makedirs(os.path.join(outdir, "trimmed"), exist_ok=True)
    if want_cells:
        os.makedirs(os.path.join(outdir, "cells"), exist_ok=True)

    def cut(n: int, total: int) -> int:
        """格边界：向下取整会把 614.4 算成 614，把上一行角色的脚切进来。用 ceil。"""
        return int(math.ceil(n * total / float(grid) - 1e-6))

    cw = W / float(grid)
    ch = H / float(grid)
    manifest = {"source": os.path.basename(src), "source_size": [W, H],
                "grid": grid, "cell": [cw, ch], "cells": []}
    rows = []
    for r in range(grid):
        row = []
        y0, y1 = cut(r, H), cut(r + 1, H)
        for c in range(grid):
            x0, x1 = cut(c, W), cut(c + 1, W)
            cell = rgba[y0:y1, x0:x1]
            name = "hero_r%dc%d" % (r, c)
            entry = {"name": name, "row": r, "col": c,
                     "cell_rect": [x0, y0, x1 - x0, y1 - y0]}
            if want_cells:
                Image.fromarray(cell, "RGBA").save(os.path.join(outdir, "cells", name + ".png"))
            box = bbox_of_alpha(cell)
            if box is None:
                entry["trim_rect"] = None
                manifest["cells"].append(entry)
                row.append((name, None, None))
                continue
            x0b, y0b, x1b, y1b = box
            # 留 1px 余量，避免裁到抗锯齿边
            x0b = max(0, x0b - 1)
            y0b = max(0, y0b - 1)
            x1b = min(cell.shape[1], x1b + 1)
            y1b = min(cell.shape[0], y1b + 1)
            crop = cell[y0b:y1b, x0b:x1b]
            Image.fromarray(crop, "RGBA").save(os.path.join(outdir, "trimmed", name + ".png"))
            # 相对整幅源图的绝对裁剪框，便于用 AtlasTexture 直接引用源图
            entry["trim_in_cell"] = [x0b, y0b, x1b - x0b, y1b - y0b]
            entry["trim_abs"] = [x0 + x0b, y0 + y0b, x1b - x0b, y1b - y0b]
            manifest["cells"].append(entry)
            row.append((name, (x1b - x0b, y1b - y0b), (y0b, y1b - 1, cell.shape[0] - 1)))
        rows.append(row)

    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)

    # 联系表
    pad = 6
    label_h = 16
    sheet = Image.new("RGBA", (grid * (int(cw) + pad) + pad, grid * (int(ch) + pad + label_h) + pad),
                      (40, 44, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for r in range(grid):
        for c in range(grid):
            if want_cells:
                cell = Image.open(os.path.join(outdir, "cells", "hero_r%dc%d.png" % (r, c))).convert("RGBA")
                px = pad + c * (int(cw) + pad)
                py = pad + r * (int(ch) + pad + label_h)
                sheet.alpha_composite(cell, (px, py))
            else:
                crop = Image.open(os.path.join(outdir, "trimmed", "hero_r%dc%d.png" % (r, c))).convert("RGBA")
                px = pad + c * (int(cw) + pad) + max(0, (int(cw) - crop.width) // 2)
                py = pad + r * (int(ch) + pad + label_h) + max(0, int(ch) - crop.height)
                sheet.alpha_composite(crop, (px, py))
            draw.text((pad + c * (int(cw) + pad) + 4, pad + r * (int(ch) + pad + label_h) + int(ch) + 1),
                      "r%dc%d" % (r, c), fill=(220, 220, 230, 255))
    sheet.convert("RGB").save(os.path.join(outdir, "_contact.png"))

    print("网格 %dx%d  单元 %.1fx%.1f  统一画布切片=%s" % (grid, grid, cw, ch, "是" if want_cells else "否"))
    for r in range(grid):
        parts = []
        for name, size, _meta in rows[r]:
            if not size:
                parts.append("%s:空" % name.replace("hero_", ""))
                continue
            parts.append("%s:%dx%d" % (name.replace("hero_", ""), size[0], size[1]))
        print("  行%d  " % r + "  ".join(parts))
    print("输出目录:", outdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
