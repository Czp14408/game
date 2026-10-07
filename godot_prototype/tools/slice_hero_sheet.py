#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 5x5 主角动作表切成可直接取用的 PNG（去白底 + 对齐裁剪 + 语义命名）。

用法:
  python tools/slice_hero_sheet.py <源图> <输出目录> [--grid 5] [--cells]

约定:
- 源图是规整 NxN 网格、纯白底，角色在格内底对齐。
- 去底用「四边洪水填充」，只吃与画布边缘连通的白色。
  不能全局把白变透明：主角穿白衬衫，全局去白会把衬衫吃穿。
- 对紧贴背景的抗锯齿像素做减边（de-fringe）：按白度给部分 alpha 并反预乘颜色，
  避免在暗色界面上出现白描边。

产物:
  source_sheet.png  整幅去底图（保留原始格位，供坐标复核）
  walk/             四方向行走序列，每方向 5 帧
                      down / up / right 取自第 0 / 2 / 1 行；left 是 right 的水平镜像
                      同一方向的所有帧用「序列并集包围盒」统一裁剪，保证播放时帧间不跳动
  pose/             语义命名的姿势帧（紧贴裁剪，不参与动画）
  manifest.json     序列与姿势的映射、包围盒、逐格坐标
  _contact.png      带行列与语义标签的联系表，便于人工指认
  cells/            统一画布切片，仅在传入 --cells 时产出（保留原格基线，供将来做动画对齐）
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
EDGE_MARGIN = 1            # 裁剪时向外多留 1px，避免切掉抗锯齿边

# 方向序列：方向名 -> (源行, 是否水平镜像)
WALK_ROWS = [
    ("down", 0, False),
    ("up", 2, False),
    ("right", 1, False),
    ("left", 1, True),
]

# 语义姿势：格位 -> (语义名, 中文标签, 用途)
POSES = [
    ((3, 0), "wave", "挥手", "打招呼／交谈"),
    ((3, 1), "salute", "敬礼", "接受任务"),
    ((3, 2), "punch", "出拳", "战斗页头像"),
    ((3, 3), "cheer_back", "背身高举", "背影举手（备用）"),
    ((3, 4), "jump", "跳跃欢呼", "胜利结算立绘"),
    ((4, 0), "think", "低头", "认输／沮丧结算立绘"),
    ((4, 1), "run", "奔跑", "快速移动姿态"),
    ((4, 2), "sprint", "冲刺", "快速移动姿态"),
    ((4, 3), "down", "倒地", "战败结算立绘"),
    ((4, 4), "pockets", "插兜站立", "闲置立绘（备用）"),
]


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
    span = float(FRINGE_THRESHOLD - 150)
    fac = np.clip((minch - 150.0) / span, 0.0, 1.0)
    alpha[ring] = 255.0 * (1.0 - fac[ring])

    a = (alpha / 255.0)[..., None]
    color = rgb.astype(np.float64)
    safe = np.maximum(a, 1e-6)
    # 反预乘：假设原像素 = 真色*a + 白*(1-a)
    unpre = (color - 255.0 * (1.0 - a)) / safe
    unpre = np.clip(unpre, 0, 255)
    return np.dstack([unpre, alpha]).astype(np.uint8)


def bbox_of_alpha(rgba: np.ndarray, thr: int = 8):
    """返回 (x0, y0, x1, y1)，右下为开区间；全透明返回 None。"""
    mask = rgba[:, :, 3] > thr
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def union_bbox(frames):
    """多个帧的包围盒并集，用于让同一序列共用一套裁剪框。"""
    box = None
    for f in frames:
        b = bbox_of_alpha(f)
        if b is None:
            continue
        if box is None:
            box = list(b)
        else:
            box = [min(box[0], b[0]), min(box[1], b[1]),
                   max(box[2], b[2]), max(box[3], b[3])]
    return None if box is None else [int(v) for v in box]


def pad_box(box, width: int, height: int, margin: int = EDGE_MARGIN):
    x0 = max(0, box[0] - margin)
    y0 = max(0, box[1] - margin)
    x1 = min(width, box[2] + margin)
    y1 = min(height, box[3] + margin)
    return [x0, y0, x1, y1]


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

    walk_dir = os.path.join(outdir, "walk")
    pose_dir = os.path.join(outdir, "pose")
    os.makedirs(walk_dir, exist_ok=True)
    os.makedirs(pose_dir, exist_ok=True)
    if want_cells:
        os.makedirs(os.path.join(outdir, "cells"), exist_ok=True)

    def cut(n: int, total: int) -> int:
        """格边界：向下取整会把 614.4 算成 614，把上一行角色的脚切进来。用 ceil。"""
        return int(math.ceil(n * total / float(grid) - 1e-6))

    cw = W / float(grid)
    ch = H / float(grid)

    # 逐格切出（含格坐标记录）
    cells = {}
    cell_rects = {}
    for r in range(grid):
        y0, y1 = cut(r, H), cut(r + 1, H)
        for c in range(grid):
            x0, x1 = cut(c, W), cut(c + 1, W)
            cells[(r, c)] = rgba[y0:y1, x0:x1]
            cell_rects[(r, c)] = [x0, y0, x1 - x0, y1 - y0]
            if want_cells:
                Image.fromarray(cells[(r, c)], "RGBA").save(
                    os.path.join(outdir, "cells", "hero_r%dc%d.png" % (r, c)))

    # 整幅去底图
    Image.fromarray(rgba, "RGBA").save(os.path.join(outdir, "source_sheet.png"))

    manifest = {
        "source": os.path.basename(src),
        "source_size": [W, H],
        "grid": grid,
        "cell": [cw, ch],
        "note": "walk 序列按「序列并集包围盒」统一裁剪，帧间不跳动；pose 为逐帧紧贴裁剪。"
                "left 由 right 水平镜像得到，运行时无需再翻转。",
        "walk": {},
        "poses": [],
        "cells": [],
    }

    # ---- 四方向行走序列 ----
    for name, row, mirrored in WALK_ROWS:
        raw = [cells[(row, c)] for c in range(grid)]
        box = pad_box(union_bbox(raw), raw[0].shape[1], raw[0].shape[0])
        x0, y0, x1, y1 = box
        files = []
        for c in range(grid):
            crop = Image.fromarray(raw[c][y0:y1, x0:x1])
            if mirrored:
                crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
            fname = "walk/%s_%d.png" % (name, c)
            crop.save(os.path.join(outdir, fname))
            files.append(fname)
        entry = {
            "frames": files,
            "size": [x1 - x0, y1 - y0],
            "source_row": row,
            "source_cells": ["hero_r%dc%d" % (row, c) for c in range(grid)],
            "mirrored": mirrored,
        }
        if mirrored:
            entry["mirror_of"] = "right"
        manifest["walk"][name] = entry

    # ---- 语义姿势帧 ----
    for (r, c), key, label, usage in POSES:
        cell = cells[(r, c)]
        box = bbox_of_alpha(cell)
        if box is None:
            print("警告：格 hero_r%dc%d 为空，跳过姿势 %s" % (r, c, key))
            continue
        x0, y0, x1, y1 = pad_box(box, cell.shape[1], cell.shape[0])
        crop = Image.fromarray(cell[y0:y1, x0:x1], "RGBA")
        fname = "pose/%s.png" % key
        crop.save(os.path.join(outdir, fname))
        manifest["poses"].append({
            "name": key, "label": label, "usage": usage,
            "file": fname, "cell": "hero_r%dc%d" % (r, c),
            "size": [x1 - x0, y1 - y0],
            "trim_in_cell": [x0, y0, x1 - x0, y1 - y0],
        })

    # ---- 逐格记录（供复核与 AtlasTexture） ----
    for r in range(grid):
        for c in range(grid):
            cell = cells[(r, c)]
            box = bbox_of_alpha(cell)
            entry = {"name": "hero_r%dc%d" % (r, c), "row": r, "col": c,
                     "cell_rect": cell_rects[(r, c)]}
            if box is None:
                entry["trim_in_cell"] = None
                entry["trim_abs"] = None
            else:
                x0, y0, x1, y1 = pad_box(box, cell.shape[1], cell.shape[0])
                entry["trim_in_cell"] = [x0, y0, x1 - x0, y1 - y0]
                entry["trim_abs"] = [cell_rects[(r, c)][0] + x0, cell_rects[(r, c)][1] + y0,
                                     x1 - x0, y1 - y0]
            manifest["cells"].append(entry)

    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)

    # ---- 联系表（标签用 ASCII，避免缺中文字体时出豆腐块） ----
    pose_at = {(r, c): key for (r, c), key, _l, _u in POSES}
    walk_at = {}
    for name, row, _m in WALK_ROWS:
        for c in range(grid):
            walk_at.setdefault((row, c), []).append(name)
    pad = 6
    label_h = 16
    sheet = Image.new("RGBA",
                      (grid * (int(cw) + pad) + pad, grid * (int(ch) + pad + label_h) + pad),
                      (40, 44, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for r in range(grid):
        for c in range(grid):
            if want_cells:
                cell = Image.open(os.path.join(outdir, "cells", "hero_r%dc%d.png" % (r, c))).convert("RGBA")
                px = pad + c * (int(cw) + pad)
                py = pad + r * (int(ch) + pad + label_h)
            else:
                key = pose_at.get((r, c))
                if key is not None:
                    crop = Image.open(os.path.join(outdir, "pose", key + ".png")).convert("RGBA")
                else:
                    crop = Image.open(os.path.join(outdir, "walk",
                                                   "%s_%d.png" % (walk_at[(r, c)][0], c))).convert("RGBA")
                px = pad + c * (int(cw) + pad) + max(0, (int(cw) - crop.width) // 2)
                py = pad + r * (int(ch) + pad + label_h) + max(0, int(ch) - crop.height)
            sheet.alpha_composite(crop, (px, py))
            tag = "r%dc%d" % (r, c)
            if pose_at.get((r, c)):
                tag += " " + pose_at[(r, c)]
            elif (r, c) in walk_at:
                tag += " " + "/".join(walk_at[(r, c)])
            draw.text((pad + c * (int(cw) + pad) + 4,
                       pad + r * (int(ch) + pad + label_h) + int(ch) + 1),
                      tag, fill=(220, 220, 230, 255))
    sheet.convert("RGB").save(os.path.join(outdir, "_contact.png"))

    print("网格 %dx%d  单元 %.1fx%.1f（源图 %dx%d）" % (grid, grid, cw, ch, W, H))
    for name, row, mirrored in WALK_ROWS:
        e = manifest["walk"][name]
        print("  walk/%-5s 行%d  %d 帧  画布 %dx%d%s"
              % (name, row, len(e["frames"]), e["size"][0], e["size"][1],
                 "（right 镜像）" if mirrored else ""))
    print("  pose/ %d 张：%s" % (len(manifest["poses"]),
                                "、".join(p["name"] for p in manifest["poses"])))
    if want_cells:
        print("  cells/ 25 张统一画布切片")
    print("输出目录:", outdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
