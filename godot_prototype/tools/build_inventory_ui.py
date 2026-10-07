"""把「背包／商店／整理共用面板」源图切成可直接摆放的面板，并测出内部三个可用分区。

用法:
  python tools/build_inventory_ui.py [--src <png>] [--out <目录>] [--preview <png>] [--edge tile|stretch]

与 build_battle_ui.py 的关系:
  同一套工序（裁框 → 测内腔 → 九宫格适配 → 量分区 → 出清单），本文件是它在
  「一块面板、内部自带三个含内容区」这种形态上的推广。战斗页是多张组件各占一块，
  这里只有**一张整面板**，物品横栏与操作条是**画在面板内部**的。

为什么不能照抄战斗页的内腔测法（见 ui修改迭代工作流.md §5.1）:
  §5.1 用「与中心同色的最长连续段」找内腔。本面板外框内**到处同色**（半透明浅蓝玻璃），
  最长连续段会落在**第一行物品横栏的内腔**上，量到的不是外框内腔。
  实测：按 §5.1 量到 (93, 1767) × (88, 211)，那正是第一行横栏。
  这里改用「逐行/逐列统计与基准色相同的比例，取首尾超过阈值的范围」定外框内腔，
  再在腔内按「非基准色像素的横向聚簇」把每一段含内容区（内含圆角矩形）与段间留白区分开。

产物:
  <out>/panel.png        整块面板，尺寸等于布局表的目标矩形，运行期 1:1 摆放
  <out>/manifest.json    面板矩形、外框内腔、三段含内容区（物品横栏一/二、底部操作条）
  --preview 另存一张整屏合成预览，用于人工确认版面（不参与运行期）
"""

import argparse
import json
import os
import sys

from PIL import Image
import numpy as np

# --- 布局表（逻辑像素，页面区左上角为原点；页面区 = 1280×720 减去 30 像素顶部状态条）---
# 依据：背包商店整理共用面板说明.md §布局与接入——建议整屏 (x=656, y=224, 宽=608, 高约200)。
# 整屏 y=224 → 页面区 y=194（减去顶部 30 像素状态条）；
# 高度按「可见框体比例」校准：可见框 1860×542，宽取 608 时等比高为 177，
# 取 177 而不是 200 → 九宫格四边与中心区都是整数倍映射，面板整体是一次等比缩放，
# 内部两条横栏的圆角与细线不会被纵向拉伸（取 200 会把内部线拉粗约 15%）。
LAYOUT = {
    "panel": (656, 194, 608, 177),
}

# 设计画布：页面区 = 1280×720 逻辑画布减去顶部 30 像素状态条。
DESIGN = (1280, 690)

# 源素材：本组件是一整块面板，不是一组分开的组件图，所以「源目录」退化为单个源图路径。
# 这是与 ui修改迭代工作流.md §7.1「新源目录 assets/ui/<组名>_v1/」的一处偏差，已记入说明文档。
SOURCE_IMAGE = os.path.join("assets", "ui", "inventory_panel_2x10_v6.png")

# 面板内部三个含内容区的语义名，自上而下。数量与顺序由测量结果校验，对不上就报错。
REGION_ORDER = ("row_a", "row_b", "op_bar")

# 每段横栏的逻辑槽位数（界面按「净宽 ÷ 槽位数」算单位格宽，不烘焙格线）。
# 依据：说明文档「两行物品分别建立十个等宽逻辑交互区域」。
ROW_SLOTS = {"row_a": 10, "row_b": 10}

# 判定阈值（集中在一处，便于换素材后复核）
ALPHA_MIN = 16        # 裁可见框时的 alpha 下限
SAME_TOL = 30         # 与基准色的 L1 距离上限（判「这一像素是不是底板」）
LINE_TOL = 80         # 判「这一像素是不是装饰线」的距离下限。
                      # 拉开两档的原因：AI 生成的玻璃底板自带纹理噪声，约一成像素与基准色
                      # 相差 30—60；用 SAME_TOL 直接取反会把噪声连成一片，找不到边线聚簇。
                      # 实测两档分别取 30 / 80 时，边线聚簇稳定且噪声不产生假聚簇。
CAVITY_FRAC = 0.85    # 某行/列「与基准色相同」的比例超过它，才算落在外框内腔里。
                      # 不能取 0.9：腔内列实测 0.88（底噪占了约一成）。
BAND_FRAC = 0.6       # 某行在腔内通色的比例超过它，才算落在某段含内容区里
EDGE_MARGIN = 10      # 段内左右边界线距外框内沿的最小距离（用于剔除贴边的装饰细条）


def crop_visible(img: Image.Image, alpha_min: int = ALPHA_MIN) -> Image.Image:
    """按 alpha 裁到可见框，丢掉画布四周的大片透明留白。"""
    alpha = np.asarray(img)[:, :, 3]
    ys = np.where((alpha > alpha_min).any(axis=1))[0]
    xs = np.where((alpha > alpha_min).any(axis=0))[0]
    return img.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def base_color(rgb: np.ndarray) -> np.ndarray:
    """基准色 = 中心 16×16 的中位色。半透明玻璃面板的底色，用来区分「底板」与「线」。"""
    h, w, _ = rgb.shape
    core = rgb[h // 2 - 8:h // 2 + 8, w // 2 - 8:w // 2 + 8].reshape(-1, 3)
    return np.median(core, axis=0)


def measure_cavity(rgb: np.ndarray, base: np.ndarray) -> tuple:
    """测外框内腔，返回 (x0, x1, y0, y1)（x1/y1 为开区间）——与 patch_geometry 的约定一致。

    为什么不用 §5.1 的最长连续段：本面板外框内到处同色，最长连续段会落在第一行
    物品横栏的内腔里（实测量到 (93,1767)×(88,211)，那是横栏不是外框内腔）。
    改法：逐行看「与基准色相同的像素占整行宽度的比例」，首尾超过 CAVITY_FRAC 的行
    就是腔内行；再在腔内行范围内逐列做同样的事得到左右边界。
    """
    same = (np.abs(rgb - base).sum(axis=2) < SAME_TOL)
    rows = same.mean(axis=1) > CAVITY_FRAC
    ys = np.where(rows)[0]
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    cols = same[y0:y1].mean(axis=0) > CAVITY_FRAC
    xs = np.where(cols)[0]
    return (int(xs.min()), int(xs.max()) + 1, y0, y1)


def _clusters(flags: np.ndarray, gap: int = 3) -> list:
    """把一维布尔数组聚成 (start, end_inclusive) 区段，间隔小于 gap 的合并。"""
    idx = np.where(flags)[0]
    out = []
    if idx.size == 0:
        return out
    start = prev = int(idx[0])
    for raw in idx[1:]:
        i = int(raw)
        if i - prev > gap:
            out.append((start, prev))
            start = i
        prev = i
    out.append((start, prev))
    return out


def measure_regions(rgb: np.ndarray, base: np.ndarray, cavity: tuple) -> tuple:
    """在腔内测出「含内容区」（自带圆角矩形的横栏／操作条），返回（源坐标区段列表, 逐行通色比例）。

    判据：腔内某一行通色（与基准色相同）比例高 → 该行不是边框线；
    段间留白同样通色，所以还要看该行的**左右边界线**：
      - 含内容区的行：腔内左右各有一处非基准色聚簇（圆角矩形的左右边线）；
      - 段间留白的行：腔内一处聚簇都没有；
      - 贴着外框内沿的装饰细条：聚簇离内沿不足 EDGE_MARGIN，按装饰剔除
        （本面板最底部有一条 14 像素细条，映射到目标尺寸只剩 4 像素，放不下任何内容）。
    """
    cx0, cx1, cy0, cy1 = cavity
    same = (np.abs(rgb - base).sum(axis=2) < SAME_TOL)
    line = (np.abs(rgb - base).sum(axis=2) > LINE_TOL)
    frac = same[:, cx0:cx1].mean(axis=1)

    runs = []
    start = None
    for y in range(cy0, cy1):
        if frac[y] > BAND_FRAC and start is None:
            start = y
        elif frac[y] <= BAND_FRAC and start is not None:
            runs.append((start, y))
            start = None
    if start is not None:
        runs.append((start, cy1))

    regions = []
    for y0, y1 in runs:
        if y1 - y0 < 6:
            continue
        mid = (y0 + y1) // 2
        clusters = _clusters(line[mid, cx0:cx1])
        if len(clusters) < 2:
            continue
        left = clusters[0]
        right = clusters[-1]
        if left[0] < EDGE_MARGIN or (cx1 - cx0) - 1 - right[1] < EDGE_MARGIN:
            continue
        x0 = cx0 + left[1] + 1
        x1 = cx0 + right[0]
        if x1 - x0 < 40:
            continue
        regions.append((x0, y0, x1, y1))
    return regions, frac


def map_region(g: dict, box: tuple) -> tuple:
    """源坐标区段 → 目标坐标区段（x, y, w, h），走 map_x/map_y 的分段线性映射。"""
    x0, y0, x1, y1 = box
    tx0, ty0 = map_x(g, x0), map_y(g, y0)
    tx1, ty1 = map_x(g, x1), map_y(g, y1)
    return (tx0, ty0, max(tx1 - tx0, 1), max(ty1 - ty0, 1))


def _tile_or_stretch(strip: Image.Image, target: tuple, mode: str) -> Image.Image:
    """把一条边框带铺到目标尺寸。mode=tile 平铺（保持原始纹样间距），stretch 拉伸。"""
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


def patch_geometry(src_size: tuple, cavity: tuple, target: tuple) -> dict:
    """九宫格几何：倍率、四条边框带、中心区尺寸。

    「源坐标 -> 目标坐标」不是等比映射：中心区被拉伸、边框带按倍率缩放。
    区段与内腔都必须走 map_x/map_y，否则按等比近似摆出来的文字会压到分隔线上。
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
    本面板目标取的是「可见框等比缩到宽 608」，所以四边与中心都是整数倍映射，
    结果等价于一次等比缩放——内部两条横栏的圆角与细线不会被拉伸变形。
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
        out.paste(_tile_or_stretch(center, (mid_w, mid_h), "stretch"), (left, top))
    return out


def build(src_path: str, out_dir: str, edge: str) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    raw = Image.open(src_path).convert("RGBA")
    visible = crop_visible(raw)
    rgb = np.asarray(visible.convert("RGB")).astype(np.int32)
    base = base_color(rgb)
    cavity = measure_cavity(rgb, base)
    regions_src, band_frac = measure_regions(rgb, base, cavity)

    names = list(REGION_ORDER)
    if len(regions_src) != len(names):
        raise SystemExit(
            "含内容区检出 %d 段，清单要求 %d 段（%s）。"
            "换素材后请核对阈值，或更新 REGION_ORDER。实测段：%s"
            % (len(regions_src), len(names), "、".join(names), regions_src))

    manifest = {
        "edge_mode": edge,
        "design": list(DESIGN),
        "layout": {k: list(v) for k, v in LAYOUT.items()},
        "rows": dict(ROW_SLOTS),
        "region_order": names,
        "panels": {},
    }

    cache = {}
    for name, rect in LAYOUT.items():
        if src_path not in cache:
            cache[src_path] = (visible, cavity)
        vis, cav = cache[src_path]
        x, y, w, h = rect
        panel = nine_patch(vis, cav, (w, h), edge)
        panel.save(os.path.join(out_dir, name + ".png"))

        vw, vh = vis.size
        g = patch_geometry((vw, vh), cav, (w, h))
        sx0, sx1, sy0, sy1 = cav
        inner = (map_x(g, sx0), map_y(g, sy0),
                 map_x(g, sx1) - map_x(g, sx0), map_y(g, sy1) - map_y(g, sy0))
        regions = {}
        for key, box in zip(names, regions_src):
            regions[key] = list(map_region(g, box))
        bands_h = [[regions[k][1], regions[k][1] + regions[k][3]] for k in names]
        manifest["panels"][name] = {
            "source": os.path.basename(src_path),
            "rect": [x, y, w, h],
            "inner": list(inner),
            "bands_h": bands_h,
            "regions": regions,
            "source_visible": [vw, vh],
            "source_cavity": list(cav),
            "source_regions": {k: list(b) for k, b in zip(names, regions_src)},
            "scan": {
                "base_color": [int(v) for v in base],
                "band_frac_min": round(float(band_frac[sy0:sy1].min()), 3),
                "band_frac_max": round(float(band_frac[sy0:sy1].max()), 3),
            },
        }

    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=1)
    return manifest


def main() -> int:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(here, SOURCE_IMAGE))
    ap.add_argument("--out", default=os.path.join(here, "assets", "ui", "inventory_v1"))
    ap.add_argument("--preview", default="")
    ap.add_argument("--edge", default="tile", choices=["tile", "stretch"])
    args = ap.parse_args()

    manifest = build(args.src, args.out, args.edge)
    print("面板 %d 张 -> %s（边缘模式 %s）" % (len(manifest["panels"]), args.out, args.edge))
    for name, info in manifest["panels"].items():
        print("  %-8s rect=%s inner=%s" % (name, info["rect"], info["inner"]))
        for key in manifest["region_order"]:
            print("      %-7s %s" % (key, info["regions"][key]))

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
