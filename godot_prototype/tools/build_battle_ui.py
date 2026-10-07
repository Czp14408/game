"""把 assets/ui/components_v1 的七张组件按固定布局切成可直接摆放的面板。

用法:
  python tools/build_battle_ui.py [--out <目录>] [--preview <png>] [--edge tile|stretch]

为什么要这道工序:
- 组件是 AI 生成的，每张画布带大量透明留白（生命槽可见部分只占画布 12% 高度），
  直接把整张画布压进目标框会把框压扁，所以先按 alpha 裁到可见框。
- 组件长宽比与布局表的目标矩形不一致，且角部有铆钉与古铜内沿。
  这里按「九宫格」规则适配：角部与边框带按比例保留，边缘按 edge 模式处理，
  中心（纯平板区）拉伸。绝不把整张图线性缩放到目标框。
- 边框带宽度由内腔（与中心同色的连通区）投影测得，不用肉眼估。

产物:
  <out>/<name>.png      每个面板一张，尺寸等于布局表中的目标矩形，运行期 1:1 摆放
  <out>/manifest.json   面板尺寸、内腔矩形（供界面画十格线与生命填充）、来源信息
  --preview 另存一张整屏合成预览，用于人工确认版面（不参与运行期）
"""

import argparse
import json
import os
import sys

from PIL import Image
import numpy as np

# --- 布局表（逻辑像素，页面区左上角为原点；页面区 = 1280×720 减去 30 像素顶部状态条）---
# 依据：战斗UI组件与组合说明.md 第 2 节，纵向按实际可用高度 690 压缩，
# 保证「左右列对齐、栏位不重叠、生命槽独立、两侧区块等高」四条不变式。
# 双方区块各 300 高：头像 160 + 8 + 名称 32 + 8 + 状态 92 = 300；
# 中列 72 + 8 + 40 + 12 + 168 = 300。
BLOCK_H = 300

LAYOUT = {
    # 敌方（上半）：区块顶 16
    "portrait_enemy": (16, 16, 160, 160),
    "name_enemy": (16, 184, 160, 32),
    "status_enemy": (16, 224, 160, 92),
    "skill_enemy": (192, 16, 820, 72),
    "health_enemy": (192, 96, 820, 40),
    "tray_enemy": (192, 148, 820, 168),
    # 中央计时
    "middle": (16, 328, 996, 36),
    # 玩家（下半）：区块顶 376
    "portrait_player": (16, 376, 160, 160),
    "name_player": (16, 544, 160, 32),
    "status_player": (16, 584, 160, 92),
    "skill_player": (192, 376, 820, 72),
    "health_player": (192, 456, 820, 40),
    "tray_player": (192, 508, 820, 168),
    # 右侧操作栏
    "operations": (1028, 16, 236, 660),
}

# 设计画布：页面区 = 1280×720 逻辑画布减去顶部 30 像素状态条。
# 第 2 节的表按整屏 720 高排到 y=704，这里按实际可用的 690 高压缩纵向节奏，
# 不变式（左右列对齐、栏位不重叠、生命槽独立、两侧区块等高 300）全部保持。
DESIGN = (1280, 690)

# 不属于页面布局的额外面板：暂停弹窗。不参与排版与不重叠检查。
EXTRA = {
    "modal": (0, 0, 460, 236),
}

# 面板 -> 源组件
SOURCE = {
    "portrait_enemy": "portrait_frame.png",
    "portrait_player": "portrait_frame.png",
    "name_enemy": "middle_strip.png",
    "name_player": "middle_strip.png",
    "status_enemy": "status_panel.png",
    "status_player": "status_panel.png",
    "skill_enemy": "skill_strip.png",
    "skill_player": "skill_strip.png",
    "health_enemy": "health_trough.png",
    "health_player": "health_trough.png",
    "tray_enemy": "item_tray.png",
    "tray_player": "item_tray.png",
    "middle": "middle_strip.png",
    "operations": "operations_panel.png",
    "modal": "status_panel.png",
}


def crop_visible(img: Image.Image, alpha_min: int = 16) -> Image.Image:
    """按 alpha 裁到可见框，丢掉画布四周的大片透明留白。"""
    alpha = np.asarray(img)[:, :, 3]
    ys = np.where((alpha > alpha_min).any(axis=1))[0]
    xs = np.where((alpha > alpha_min).any(axis=0))[0]
    return img.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def measure_cavity(img: Image.Image) -> tuple:
    """测内腔（与中心同色的连通区）。

    返回 (x0, x1, y0, y1)，x1/y1 为开区间。
    做法：以中心 16×16 的中位色为基准色，统计每列/每行属于基准色的比例，
    取比例超过「峰值 60% 且不低于 15%」的最长连续段。
    为什么不用「从中心向外扫到变色」：横条边框上的木格挡会让扫描提前停下，
    左右测量结果会不对称（实测右 2.4% / 左 4.7%）。
    """
    return _cavity_and_mask(img)[0]


def _cavity_and_mask(img: Image.Image) -> tuple:
    rgb = np.asarray(img.convert("RGB")).astype(np.int32)
    h, w, _ = rgb.shape
    core = rgb[h // 2 - 8:h // 2 + 8, w // 2 - 8:w // 2 + 8].reshape(-1, 3)
    base = np.median(core, axis=0)
    same = np.abs(rgb - base).sum(axis=2) < 30

    def longest(frac: np.ndarray) -> tuple:
        thr = max(float(frac.max()) * 0.6, 0.15)
        idx = np.where(frac > thr)[0]
        best = (int(idx[0]), int(idx[0]))
        start = prev = int(idx[0])
        for i in idx[1:]:
            i = int(i)
            if i - prev > 1:
                if prev - start > best[1] - best[0]:
                    best = (start, prev)
                start = i
            prev = i
        if prev - start > best[1] - best[0]:
            best = (start, prev)
        return best

    cx = longest(same.mean(axis=0))
    ry = longest(same.mean(axis=1))
    return (cx[0], cx[1] + 1, ry[0], ry[1] + 1), same


def _tile_or_stretch(strip: Image.Image, target: tuple, mode: str) -> Image.Image:
    """把一条边框带铺到目标尺寸。mode=tile 平铺（保持铆钉原始间距），stretch 拉伸。"""
    tw, th = target
    if tw <= 0 or th <= 0:
        return Image.new("RGBA", (max(tw, 0), max(th, 0)), (0, 0, 0, 0))
    if mode == "stretch":
        return strip.resize((tw, th), Image.LANCZOS)
    sw, sh = strip.size
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    if tw >= sw and th >= sh:
        for y in range(0, th, sh):
            for x in range(0, tw, sw):
                out.paste(strip, (x, y))
    else:
        # 目标比一个循环还短：居中裁一块，避免出现半截纹理
        out.paste(strip, ((tw - sw) // 2, (th - sh) // 2))
    return out


def open_bands(same: np.ndarray, span: tuple, axis: str, min_len: int = 3) -> list:
    """在「另一轴的完整范围」内检出可放内容的连续条带。

    横向条带（axis=h）扫全部行、但只在横向内腔范围内统计：这样自带分隔的
    操作栏会被分隔条切成多段，而单腔面板只会得到一条覆盖整个内腔的带。
    只在内腔范围内扫是检不出分隔的——那正是内腔的定义。
    """
    lo, hi = span
    if axis == "h":
        frac = same[:, lo:hi].mean(axis=1)
    else:
        frac = same[lo:hi, :].mean(axis=0)
    if frac.size == 0:
        return []
    thr = max(float(frac.max()) * 0.6, 0.3)
    bands = []
    start = None
    for i, v in enumerate(frac):
        if v > thr and start is None:
            start = i
        elif v <= thr and start is not None:
            bands.append((start, i))
            start = None
    if start is not None:
        bands.append((start, int(frac.size)))
    return [(a, b) for a, b in bands if b - a >= min_len]


def patch_geometry(src_size: tuple, cavity: tuple, target: tuple) -> dict:
    """九宫格几何：倍率、四条边框带、中心区尺寸。

    单独抽出来是因为「源坐标 -> 目标坐标」不是等比映射：中心区被拉伸，
    边框带按倍率缩放。内腔矩形与分隔带都必须走这套映射，
    否则拿等比缩放的近似值去摆文字，会压到分隔条上。
    """
    w0, h0 = src_size
    tw, th = target
    cx0, cx1, cy0, cy1 = cavity

    scale = min(tw / float(w0), th / float(h0))
    w1 = max(1, int(round(w0 * scale)))
    h1 = max(1, int(round(h0 * scale)))
    left = int(round(cx0 * scale))
    right = int(round((w0 - cx1) * scale))
    top = int(round(cy0 * scale))
    bottom = int(round((h0 - cy1) * scale))

    # 夹紧：边框带之和不能超过目标尺寸，否则中心区会被压成负数
    if left + right > tw:
        over = left + right - tw
        left = max(1, left - over // 2)
        right = max(1, tw - left)
    if top + bottom > th:
        over = top + bottom - th
        top = max(1, top - over // 2)
        bottom = max(1, th - top)

    return {
        "src": (w0, h0), "scale": scale, "w1": w1, "h1": h1,
        "left": left, "right": right, "top": top, "bottom": bottom,
        "mid_w": tw - left - right, "mid_h": th - top - bottom,
        "tw": tw, "th": th, "cavity": cavity,
    }


def map_x(g: dict, v: float) -> int:
    """源横坐标 -> 目标横坐标（边框带等比缩、中心区拉伸）。"""
    cx0, cx1 = g["cavity"][0], g["cavity"][1]
    if v <= cx0:
        return int(round(v * g["scale"]))
    if v >= cx1:
        return g["tw"] - int(round((g["src"][0] - v) * g["scale"]))
    span = float(cx1 - cx0)
    if span <= 0.0:
        return int(g["left"])
    return int(round(g["left"] + (v - cx0) / span * g["mid_w"]))


def map_y(g: dict, v: float) -> int:
    """源纵坐标 -> 目标纵坐标。"""
    cy0, cy1 = g["cavity"][2], g["cavity"][3]
    if v <= cy0:
        return int(round(v * g["scale"]))
    if v >= cy1:
        return g["th"] - int(round((g["src"][1] - v) * g["scale"]))
    span = float(cy1 - cy0)
    if span <= 0.0:
        return int(g["top"])
    return int(round(g["top"] + (v - cy0) / span * g["mid_h"]))


def nine_patch(src: Image.Image, cavity: tuple, target: tuple, edge: str = "tile") -> Image.Image:
    """按九宫格把可见组件适配到目标矩形。

    先整体等比「contain」缩放（保证至少一个方向正好贴合，边框带厚度不会被吃掉），
    再按内腔划出四角、四边与中心：角部原样贴、边缘按 edge 模式铺、中心拉伸。
    """
    w0, h0 = src.size
    g = patch_geometry((w0, h0), cavity, target)
    scaled = src.resize((g["w1"], g["h1"]), Image.LANCZOS)
    left, right, top, bottom = g["left"], g["right"], g["top"], g["bottom"]
    w1, h1, tw, th = g["w1"], g["h1"], g["tw"], g["th"]

    mid_w = tw - left - right
    mid_h = th - top - bottom

    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    # 四角
    out.paste(scaled.crop((0, 0, left, top)), (0, 0))
    out.paste(scaled.crop((w1 - right, 0, w1, top)), (tw - right, 0))
    out.paste(scaled.crop((0, h1 - bottom, left, h1)), (0, th - bottom))
    out.paste(scaled.crop((w1 - right, h1 - bottom, w1, h1)), (tw - right, th - bottom))
    # 上下边
    if mid_w > 0:
        out.paste(_tile_or_stretch(scaled.crop((left, 0, w1 - right, top)), (mid_w, top), edge), (left, 0))
        out.paste(_tile_or_stretch(scaled.crop((left, h1 - bottom, w1 - right, h1)), (mid_w, bottom), edge),
                  (left, th - bottom))
    # 左右边
    if mid_h > 0:
        out.paste(_tile_or_stretch(scaled.crop((0, top, left, h1 - bottom)), (left, mid_h), edge), (0, top))
        out.paste(_tile_or_stretch(scaled.crop((w1 - right, top, w1, h1 - bottom)), (right, mid_h), edge),
                  (tw - right, top))
    # 中心
    if mid_w > 0 and mid_h > 0:
        center = scaled.crop((left, top, w1 - right, h1 - bottom))
        mode = "stretch" if edge == "tile" else "stretch"
        out.paste(_tile_or_stretch(center, (mid_w, mid_h), mode), (left, top))
    return out


def build(src_dir: str, out_dir: str, edge: str) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    manifest = {
        "edge_mode": edge,
        "design": list(DESIGN),
        "layout": {k: list(v) for k, v in LAYOUT.items()},
        "extra": {k: list(v) for k, v in EXTRA.items()},
        "panels": {},
    }
    cache = {}
    for name, rect in list(LAYOUT.items()) + list(EXTRA.items()):
        src_path = os.path.join(src_dir, SOURCE[name])
        if src_path not in cache:
            raw = Image.open(src_path).convert("RGBA")
            visible = crop_visible(raw)
            cavity, same = _cavity_and_mask(visible)
            cache[src_path] = (visible, cavity, same)
        visible, cavity, same = cache[src_path]
        x, y, w, h = rect
        panel = nine_patch(visible, cavity, (w, h), edge)
        panel.save(os.path.join(out_dir, name + ".png"))

        vw, vh = visible.size
        g = patch_geometry((vw, vh), cavity, (w, h))
        sx0, sx1, sy0, sy1 = cavity
        inner = (map_x(g, sx0), map_y(g, sy0),
                 map_x(g, sx1) - map_x(g, sx0), map_y(g, sy1) - map_y(g, sy0))
        bands_h = [
            (map_y(g, b0), map_y(g, b1))
            for b0, b1 in open_bands(same, (sx0, sx1), "h")
        ]
        bands_v = [
            (map_x(g, b0), map_x(g, b1))
            for b0, b1 in open_bands(same, (sy0, sy1), "v")
        ]
        manifest["panels"][name] = {
            "source": SOURCE[name],
            "rect": [x, y, w, h],
            "inner": list(inner),
            "bands_h": [list(b) for b in bands_h],
            "bands_v": [list(b) for b in bands_v],
            "source_visible": [vw, vh],
            "source_cavity": [sx0, sy0, sx1, sy1],
        }
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=1)
    return manifest


def main() -> int:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(here, "assets", "ui", "components_v1"))
    ap.add_argument("--out", default=os.path.join(here, "assets", "ui", "battle_v1"))
    ap.add_argument("--preview", default="")
    ap.add_argument("--edge", default="tile", choices=["tile", "stretch"])
    args = ap.parse_args()

    manifest = build(args.src, args.out, args.edge)
    print("面板 %d 张 -> %s（边缘模式 %s）" % (len(manifest["panels"]), args.out, args.edge))
    for name, info in manifest["panels"].items():
        print("  %-16s rect=%-22s inner=%-22s bands_h=%s bands_v=%s" % (
            name, info["rect"], info["inner"], info["bands_h"], info["bands_v"]))

    if args.preview:
        os.makedirs(os.path.dirname(os.path.abspath(args.preview)), exist_ok=True)
        sheet = Image.new("RGBA", (DESIGN[0], DESIGN[1] + 30), (23, 23, 26, 255))
        for name in LAYOUT:
            info = manifest["panels"][name]
            panel = Image.open(os.path.join(args.out, name + ".png")).convert("RGBA")
            x, y, _w, _h = info["rect"]
            sheet.alpha_composite(panel, (x, y + 30))
        sheet.convert("RGB").save(args.preview)
        print("预览 ->", args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
