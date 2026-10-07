#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通用角色动作表切图管线（色键底 / 任意网格 / 动作行配置）。

主角管线是 tools/slice_hero_sheet.py（5x5 白底专用）；本工具是其泛化版，
用于后续角色（当前：山贼 bandit，8x8 绿底）。约定不变：
- 去底用「四边洪水填充」+ 内部封闭洞并洞，只吃确定的背景色。
  不能全局按色替换：会把角色身上相近色吃穿（主角白衬衫、山贼深褐披风同理）。
- 格边界用 ceil：向下取整会把上一行角色的脚切进下一格。
- 对紧贴背景的抗锯齿像素做减边（de-fringe）：按「离底色的距离」给部分 alpha
  并按底色反预乘，避免在暗色界面上出现底色描边（白底白边 / 绿底绿边同理）。
- 同一序列的所有帧用「序列并集包围盒」统一裁剪，保证播放时帧间不跳动。

用法:
  python tools/slice_character_sheet.py <源图> <输出目录> --preset bandit [--cells]

新增角色时在 LAYOUTS 里加一份 preset（行号从 0 起，frames 可少于该行格数，
用 start 指定起始列；mirrored=True 表示由同行右向帧水平镜像得到）。

实测校准（山贼 1024x1024 绿底 RGB≈(10,248,4)）：
- 角色最深色离底色 maxdiff >= 150；JPEG 混色带落在 0..150。
  减边带取 130：中段混色拿到部分 alpha，不会被当成实体绿留下。
- 内部封闭绿洞（腿缝／矛杆与身体之间）实测最大 70px 高，洞上限取 140 留余量。
- 洞判定比洪水更严（60）：只吃接近纯底色的洞，避免误吃角色相近色。
"""

import json
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

EDGE_MARGIN = 1          # 裁剪时向外多留 1px，避免切掉抗锯齿边
FLOOD_DIST = 100         # 洪水填充判定「与底色足够近」的通道距离
HOLE_DIST = 60           # 内部封闭洞判定：比洪水更严（只吃接近纯底色的洞）
HOLE_MAX_SIDE = 140      # 内部封闭底色洞的最大边长（实测最大洞 70px，留余量）
FRINGE_DIST = 130        # 减边带：混色像素按「离底色距离/该值」给 alpha
SPECK_MIN_AREA = 48      # 孤立小斑点并回背景的面积阈值

# ---------------------------------------------------------------------------
# 角色布局 preset：行语义映射（行号 0 起）
#   walk: 方向名 -> (行, 是否镜像)；镜像仅用于「源图只画了右向」的表
#   actions: 动作名 -> (行, 起始列, 帧数)
# ---------------------------------------------------------------------------
LAYOUTS = {
    "bandit": {
        "note": "山贼 8x8 绿底：行0-3 四方向行走，行4 前刺，行5 突进刺，"
                "行6 格挡2+盾击4+受击2，行7 待机2+倒地死亡6。左右向源图原生齐全。",
        "cols": 8,
        "rows": 8,
        "walk": {
            "down": (0, False),
            "right": (1, False),
            "up": (2, False),
            "left": (3, False),   # 源图行3 原生左向，不镜像
        },
        "actions": {
            "thrust": (4, 0, 8),   # 前刺攻击
            "lunge": (5, 0, 8),    # 突进刺
            "guard": (6, 0, 2),    # 举盾格挡
            "slash": (6, 2, 4),    # 盾击横扫
            "hit": (6, 6, 2),      # 受击
            "idle": (7, 0, 2),     # 待机呼吸
            "death": (7, 2, 6),    # 倒地死亡
        },
    },
    "bandit_spear": {
        "note": "铁盔矛盾山贼 8x8 绿底：与 bandit（白兜帽矛山贼）同行语义同构——"
                "行0-3 四方向行走，行4 前刺，行5 突进刺，行6 格挡2+挥砍4+受击2，"
                "行7 待机2+倒地死亡6。",
        "cols": 8,
        "rows": 8,
        "walk": {
            "down": (0, False),
            "right": (1, False),
            "up": (2, False),
            "left": (3, False),
        },
        "actions": {
            "thrust": (4, 0, 8),
            "lunge": (5, 0, 8),
            "guard": (6, 0, 2),
            "slash": (6, 2, 4),
            "hit": (6, 6, 2),
            "idle": (7, 0, 2),
            "death": (7, 2, 6),
        },
    },
    "bandit_hammer": {
        "note": "巨锤山贼 8x8 绿底：行0-3 四方向行走，行4 短刀连击8帧，"
                "行5 巨锤砸地8帧，行6 持刀戒备4+挥拳怒吼4（无受击行，受击可复用"
                "death 前段或后续补素材），行7 待机2+倒地死亡6。",
        "cols": 8,
        "rows": 8,
        "walk": {
            "down": (0, False),
            "right": (1, False),
            "up": (2, False),
            "left": (3, False),
        },
        "actions": {
            "knife": (4, 0, 8),    # 短刀连击
            "smash": (5, 0, 8),    # 巨锤砸地
            "guard": (6, 0, 4),    # 持刀戒备
            "taunt": (6, 4, 4),    # 挥拳怒吼
            "idle": (7, 0, 2),
            "death": (7, 2, 6),
        },
    },
}


# ---------------------------------------------------------------------------
# 去底
# ---------------------------------------------------------------------------
def estimate_bg(rgb: np.ndarray) -> np.ndarray:
    """用四角 8x8 中值估计底色（绿幕 / 白底通吃）。"""
    corners = [rgb[:8, :8].reshape(-1, 3), rgb[:8, -8:].reshape(-1, 3),
               rgb[-8:, :8].reshape(-1, 3), rgb[-8:, -8:].reshape(-1, 3)]
    return np.median(np.concatenate(corners), axis=0)


def flood_background(rgb: np.ndarray, bg: np.ndarray,
                     thr: int = FLOOD_DIST) -> np.ndarray:
    """从四边洪水填充，返回「确定是背景」的布尔掩码。"""
    h, w, _ = rgb.shape
    near = np.abs(rgb.astype(int) - bg[None, None, :]).max(axis=2) <= thr
    isbg = np.zeros((h, w), dtype=bool)
    queue = deque()

    def push(y: int, x: int) -> None:
        if near[y, x] and not isbg[y, x]:
            isbg[y, x] = True
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
    return isbg


def components(mask: np.ndarray):
    """连通域列表（4 邻接），每项是 [(y,x), ...]。"""
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    comps = []
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            queue = deque([(sy, sx)])
            seen[sy, sx] = True
            comp = []
            while queue:
                y, x = queue.popleft()
                comp.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            comps.append(comp)
    return comps


def close_interior_holes(isbg: np.ndarray, rgb: np.ndarray,
                         bg: np.ndarray) -> np.ndarray:
    """把角色内部封闭的底色小洞并进背景（洪水到不了的腿缝／腋下绿块）。
    洞判定比洪水更严（HOLE_DIST），边长上限 HOLE_MAX_SIDE 覆盖实测最大洞。"""
    near = np.abs(rgb.astype(int) - bg[None, None, :]).max(axis=2) <= HOLE_DIST
    rest = near & ~isbg
    if not rest.any():
        return isbg
    out = isbg.copy()
    for comp in components(rest):
        ys = [p[0] for p in comp]
        xs = [p[1] for p in comp]
        if (max(ys) - min(ys) <= HOLE_MAX_SIDE
                and max(xs) - min(xs) <= HOLE_MAX_SIDE):
            for y, x in comp:
                out[y, x] = True
    return out


def drop_specks(isbg: np.ndarray, min_area: int = SPECK_MIN_AREA) -> np.ndarray:
    """把「非背景但极小」的孤立块并回背景（JPEG 噪点会制造这类斑点）。"""
    content = ~isbg
    out = isbg.copy()
    for comp in components(content):
        if len(comp) < min_area:
            for y, x in comp:
                out[y, x] = True
    return out


def to_rgba(rgb: np.ndarray):
    """去底 + 减边，返回 (RGBA, 底色)。反预乘按底色算。"""
    h, w, _ = rgb.shape
    bg = estimate_bg(rgb)
    isbg = drop_specks(close_interior_holes(flood_background(rgb, bg), rgb, bg))

    # 与背景相邻（2px 内）、本身在抗锯齿带里的像素：按「离底色的距离」给部分 alpha
    dilated = np.zeros_like(isbg)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1),
                   (1, 1), (1, -1), (-1, 1), (-1, -1)):
        dilated |= np.roll(np.roll(isbg, dy, axis=0), dx, axis=1)
    for dy, dx in ((2, 0), (-2, 0), (0, 2), (0, -2)):
        dilated |= np.roll(np.roll(isbg, dy, axis=0), dx, axis=1)
    ring = dilated & ~isbg

    dist = np.abs(rgb.astype(np.float64) - bg[None, None, :]).max(axis=2)
    alpha = np.full((h, w), 255.0)
    alpha[isbg] = 0.0
    alpha[ring] = 255.0 * np.clip(dist[ring] / float(FRINGE_DIST), 0.0, 1.0)

    a = (alpha / 255.0)[..., None]
    color = rgb.astype(np.float64)
    safe = np.maximum(a, 1e-6)
    # 反预乘：原像素 = 真色*a + 底色*(1-a)
    unpre = (color - bg[None, None, :] * (1.0 - a)) / safe
    unpre = np.clip(unpre, 0, 255)
    return np.dstack([unpre, alpha]).astype(np.uint8), bg


# ---------------------------------------------------------------------------
# 裁剪
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, outdir = sys.argv[1], sys.argv[2]
    preset = "bandit"
    if "--preset" in sys.argv:
        preset = sys.argv[sys.argv.index("--preset") + 1]
    want_cells = "--cells" in sys.argv
    layout = LAYOUTS[preset]

    img = Image.open(src).convert("RGB")
    W, H = img.size
    cols = layout.get("cols", 8)
    rows = layout.get("rows", 8)
    rgba, bg = to_rgba(np.asarray(img))

    def cell_cut(n: int, total: int, axis: int) -> int:
        """格边界：向下取整会把上一行角色的脚切进来，用 ceil。
        axis: 0 = x 按 cols 均分, 1 = y 按 rows 均分。"""
        n_div = cols if axis == 0 else rows
        return int(math.ceil(n * total / float(n_div) - 1e-6))

    cw = W / float(cols)
    ch = H / float(rows)

    walk_dir = os.path.join(outdir, "walk")
    act_dir = os.path.join(outdir, "action")
    os.makedirs(walk_dir, exist_ok=True)
    os.makedirs(act_dir, exist_ok=True)
    if want_cells:
        os.makedirs(os.path.join(outdir, "cells"), exist_ok=True)

    # 逐格切出
    cells = {}
    cell_rects = {}
    for r in range(rows):
        y0, y1 = cell_cut(r, H, 1), cell_cut(r + 1, H, 1)
        for c in range(cols):
            x0, x1 = cell_cut(c, W, 0), cell_cut(c + 1, W, 0)
            cells[(r, c)] = rgba[y0:y1, x0:x1]
            cell_rects[(r, c)] = [x0, y0, x1 - x0, y1 - y0]
            if want_cells:
                Image.fromarray(cells[(r, c)], "RGBA").save(
                    os.path.join(outdir, "cells", "%s_r%dc%d.png" % (preset, r, c)))

    # 整幅去底图
    Image.fromarray(rgba, "RGBA").save(os.path.join(outdir, "source_sheet.png"))

    manifest = {
        "character": preset,
        "source": os.path.basename(src),
        "source_size": [W, H],
        "grid": [rows, cols],
        "cell": [cw, ch],
        "background_rgb": [int(v) for v in bg],
        "note": "walk/action 序列按「序列并集包围盒」统一裁剪，帧间不跳动。"
                "mirrored=true 的方向由右向帧水平镜像得到，运行时无需再翻转。",
        "walk": {},
        "actions": {},
        "cells": [],
    }

    # ---- 四方向行走序列 ----
    for name, (row, mirrored) in layout["walk"].items():
        raw = [cells[(row, c)] for c in range(cols)]
        box = pad_box(union_bbox(raw), raw[0].shape[1], raw[0].shape[0])
        x0, y0, x1, y1 = box
        files = []
        for c in range(cols):
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
            "mirrored": mirrored,
        }
        if mirrored:
            entry["mirror_of"] = "right"
        manifest["walk"][name] = entry

    # ---- 动作序列 ----
    for name, (row, start, nframes) in layout["actions"].items():
        raw = [cells[(row, start + i)] for i in range(nframes)]
        box = pad_box(union_bbox(raw), raw[0].shape[1], raw[0].shape[0])
        x0, y0, x1, y1 = box
        files = []
        for i in range(nframes):
            fname = "action/%s_%d.png" % (name, i)
            Image.fromarray(raw[i][y0:y1, x0:x1]).save(os.path.join(outdir, fname))
            files.append(fname)
        manifest["actions"][name] = {
            "frames": files,
            "size": [x1 - x0, y1 - y0],
            "source_row": row,
            "source_start_col": start,
        }

    # ---- 逐格记录（供复核与 AtlasTexture） ----
    for r in range(rows):
        for c in range(cols):
            box = bbox_of_alpha(cells[(r, c)])
            entry = {"name": "%s_r%dc%d" % (preset, r, c), "row": r, "col": c,
                     "cell_rect": cell_rects[(r, c)]}
            if box is None:
                entry["trim_in_cell"] = None
            else:
                x0, y0, x1, y1 = pad_box(box, cells[(r, c)].shape[1], cells[(r, c)].shape[0])
                entry["trim_in_cell"] = [x0, y0, x1 - x0, y1 - y0]
                entry["trim_abs"] = [cell_rects[(r, c)][0] + x0, cell_rects[(r, c)][1] + y0,
                                     x1 - x0, y1 - y0]
            manifest["cells"].append(entry)

    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)

    # ---- 联系表（标签用 ASCII，避免缺中文字体时出豆腐块） ----
    pad = 6
    label_h = 16
    sheet = Image.new("RGBA",
                      (cols * (int(cw) + pad) + pad, rows * (int(ch) + pad + label_h) + pad),
                      (40, 44, 52, 255))
    draw = ImageDraw.Draw(sheet)
    act_at = {}
    for name, (row, start, nframes) in layout["actions"].items():
        for i in range(nframes):
            act_at.setdefault((row, start + i), []).append(name)
    walk_at = {}
    for name, (row, _m) in layout["walk"].items():
        for c in range(cols):
            walk_at.setdefault((row, c), []).append(name)
    for r in range(rows):
        for c in range(cols):
            if want_cells:
                crop = Image.open(os.path.join(
                    outdir, "cells", "%s_r%dc%d.png" % (preset, r, c))).convert("RGBA")
                px = pad + c * (int(cw) + pad)
                py = pad + r * (int(ch) + pad + label_h)
            else:
                if (r, c) in walk_at:
                    crop = Image.open(os.path.join(
                        outdir, "walk", "%s_%d.png" % (walk_at[(r, c)][0], c))).convert("RGBA")
                elif (r, c) in act_at:
                    nm = act_at[(r, c)][0]
                    crop = Image.open(os.path.join(
                        outdir, "action", "%s_%d.png" % (nm, c - layout["actions"][nm][1]))).convert("RGBA")
                else:
                    crop = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
                px = pad + c * (int(cw) + pad) + max(0, (int(cw) - crop.width) // 2)
                py = pad + r * (int(ch) + pad + label_h) + max(0, int(ch) - crop.height)
            sheet.alpha_composite(crop, (px, py))
            tag = "r%dc%d" % (r, c)
            if (r, c) in walk_at:
                tag += " " + "/".join(walk_at[(r, c)])
            elif (r, c) in act_at:
                tag += " " + "/".join(act_at[(r, c)])
            draw.text((pad + c * (int(cw) + pad) + 4,
                       pad + r * (int(ch) + pad + label_h) + int(ch) + 1),
                      tag, fill=(220, 220, 230, 255))
    sheet.convert("RGB").save(os.path.join(outdir, "_contact.png"))

    # ---- 自检：不透明且接近底色的残留像素应≈0 ----
    # 注意不能用「绿色占优」当泄漏判据：山贼美术本身带暗绿（斗篷/盾纹）。
    bgv = bg.astype(int)
    d_bg = np.abs(rgba[:, :, :3].astype(int) - bgv[None, None, :]).max(axis=2)
    op = rgba[:, :, 3] > 200
    resid = int((op & (d_bg <= 60)).sum())
    semi = int(((rgba[:, :, 3] > 0) & (rgba[:, :, 3] < 255)).sum())
    print("网格 %dx%d  单元 %.1fx%.1f（源图 %dx%d，底色 RGB=%s）"
          % (rows, cols, cw, ch, W, H, [int(v) for v in bg]))
    for name, (row, _m) in layout["walk"].items():
        e = manifest["walk"][name]
        print("  walk/%-5s 行%d  %d 帧  画布 %dx%d%s"
              % (name, row, len(e["frames"]), e["size"][0], e["size"][1],
                 "（右向镜像）" if e["mirrored"] else ""))
    for name, (row, start, nframes) in layout["actions"].items():
        e = manifest["actions"][name]
        print("  action/%-6s 行%d 列%d起  %d 帧  画布 %dx%d"
              % (name, row, start, len(e["frames"]), e["size"][0], e["size"][1]))
    print("  残留底色像素(不透明且离底色<=60): %d（应≈0，>200 需人工复核）" % resid)
    print("  半透明边缘像素: %d（减边带，正常应为少量）" % semi)
    print("输出目录:", outdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
