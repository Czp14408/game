# -*- coding: utf-8 -*-
"""生成「主角形象接入效果预览」（仅预览，不改工程）。"""
from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/msyh.ttc"
FB = "C:/Windows/Fonts/msyhbd.ttc"

def f(size, bold=False):
    return ImageFont.truetype(FB if bold else FONT, size)

BG = (23, 23, 28)
PANEL = (38, 38, 46)
BORDER = (77, 77, 92)
TEXT = (230, 230, 235)
MUTED = (158, 158, 173)
ACCENT = (217, 179, 107)
PLAYER = (92, 158, 242)
ENEMY = (222, 89, 89)
HP = (199, 71, 77)
MERCHANT = (107, 199, 115)
SHEET = (15, 15, 19)

HERO = "godot_prototype/assets/hero/trimmed/"


def panel(d, box, title):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=6, fill=PANEL, outline=BORDER, width=1)
    d.text((x0 + 12, y0 + 10), title, font=f(15, True), fill=TEXT)


def hbar(d, x, y, w, h, ratio, color):
    d.rectangle((x, y, x + w, y + h), fill=(52, 52, 60))
    d.rectangle((x, y, x + int(w * ratio), y + h), fill=color)


def portrait(canvas, name, cx, cy, scale):
    im = Image.open(HERO + "hero_" + name + ".png").convert("RGBA")
    nw, nh = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    im = im.resize((nw, nh), Image.NEAREST)
    canvas.alpha_composite(im, (int(cx - nw / 2), int(cy)))


# ---------------------------------------------------------------- 战斗页对照
def battle(with_portrait):
    W, H = 640, 380
    c = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(c)
    d.text((16, 10), "自动战斗 · 世界遭遇", font=f(16, True), fill=TEXT)

    py, ph = 44, 320
    panel(d, (16, py, 300, py + ph), "玩家（武者）")
    if with_portrait:
        portrait(c, "r0c0", 80, py + 30, 0.46)
        portrait(c, "r3c2", 196, py + 42, 0.44)
        d.text((30, py + 150), "常驻立绘", font=f(11), fill=MUTED)
        d.text((150, py + 150), "战斗姿态", font=f(11), fill=MUTED)
        ty = py + 180
    else:
        ty = py + 34
    d.text((30, ty), "生命 120 / 120", font=f(13), fill=TEXT)
    hbar(d, 30, ty + 20, 250, 12, 1.0, PLAYER)
    d.text((30, ty + 40), "护盾 0｜燃烧 2 层｜冷却就绪 2/3", font=f(11), fill=MUTED)
    d.text((30, ty + 60), "物品（释放次数／剩余冷却）", font=f(12), fill=ACCENT)
    for i, (n, s) in enumerate([("· 青铜长刀（青铜）2 格", "2／0 秒"),
                                ("· 护身佩（青铜）2 格", "1／8 秒"),
                                ("· 短刃（青铜）1 格", "3／0 秒")]):
        d.text((30, ty + 80 + i * 18), n, font=f(12), fill=TEXT)
        d.text((232, ty + 80 + i * 18), s, font=f(11), fill=MUTED)

    panel(d, (316, py, 480, py + ph), "战斗进程")
    d.text((330, py + 34), "第 214 步 / 0.1 秒每步", font=f(12), fill=TEXT)
    for i, t in enumerate(["×1", "×2", "×4"]):
        d.rounded_rectangle((330 + i * 44, py + 54, 366 + i * 44, py + 78), radius=4, fill=(48, 48, 58))
        d.text((340 + i * 44, py + 59), t, font=f(11), fill=TEXT)
    d.rounded_rectangle((330, py + 86, 466, py + 110), radius=4, fill=(48, 48, 58))
    d.text((338, py + 91), "暂停／继续（Esc）", font=f(11), fill=TEXT)
    d.text((330, py + 124), "事件日志（最近 16 条）", font=f(12), fill=ACCENT)
    d.rectangle((330, py + 144, 466, py + 300), fill=(30, 30, 38))
    for i, t in enumerate(["玩家以长刀造成 14", "对手护盾抵消 6", "燃烧造成 4", "对手释放重锤 22", "玩家治疗 +5"]):
        d.text((334, py + 150 + i * 17), t, font=f(11), fill=MUTED)

    panel(d, (496, py, 624, py + ph), "对手（山贼头目）")
    d.text((510, py + 34), "（无形象素材）", font=f(12), fill=ENEMY)
    d.rectangle((510, py + 54, 610, py + 134), outline=(70, 70, 80))
    d.line((510, py + 54, 610, py + 134), fill=(70, 70, 80))
    d.line((510, py + 134, 610, py + 54), fill=(70, 70, 80))
    d.text((510, py + 148), "生命 160 / 160", font=f(12), fill=TEXT)
    hbar(d, 510, py + 166, 100, 12, 1.0, ENEMY)
    d.text((510, py + 190), "物品 3 件", font=f(11), fill=MUTED)
    return c


# ---------------------------------------------------------------- 结算页
def result():
    W, H = 640, 260
    c = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(c)
    for i, (label, pose, col, note) in enumerate([
            ("试炼结束 · 通关", "r3c4", MERCHANT, "胜利立绘 · 欢呼"),
            ("试炼结束 · 战败", "r4c3", ENEMY, "战败立绘 · 倒地")]):
        x = 16 + i * 312
        d.rounded_rectangle((x, 12, x + 300, 248), radius=6, fill=PANEL, outline=BORDER, width=1)
        d.text((x + 12, 22), label, font=f(15, True), fill=col)
        d.text((x + 12, 50), "结束原因：生命归零", font=f(12), fill=TEXT)
        if pose == "r4c3":
            portrait(c, pose, x + 150, 96, 0.62)
        else:
            portrait(c, pose, x + 150, 84, 0.62)
        d.text((x + 12, 210), note, font=f(11), fill=MUTED)
        d.text((x + 12, 226), "生命 0.0 / 120.0｜货币 12", font=f(11), fill=TEXT)
    return c


def band(title, subtitle):
    im = Image.new("RGBA", (1300, 46), SHEET + (255,))
    d = ImageDraw.Draw(im)
    d.text((16, 6), title, font=f(17, True), fill=ACCENT)
    d.text((16, 27), subtitle, font=f(11), fill=MUTED)
    return im


def main():
    parts = []
    parts.append(band("① 战斗页：玩家侧接入主角立绘（左：不接 ／ 右：接入）",
                      "接入后玩家侧上半部放常驻立绘＋战斗姿态；对手侧仍无素材，会明显空一块"))
    row = Image.new("RGBA", (1300, 380), BG + (255,))
    row.alpha_composite(battle(False), (6, 0))
    row.alpha_composite(battle(True), (654, 0))
    parts.append(row)

    parts.append(band("② 结算页：用现有姿势直接做胜负立绘",
                      "第 4 行 r3c4（欢呼）可作胜利、第 5 行 r4c3（倒地）可作战败，无需新素材"))
    parts.append(result())

    total_h = sum(p.height for p in parts) + 8 * len(parts)
    out = Image.new("RGBA", (1300, total_h), SHEET + (255,))
    y = 0
    for p in parts:
        out.alpha_composite(p, (0, y))
        y += p.height + 8
    out.convert("RGB").save(".scratch/hero_ui_mock.png")
    print("saved", out.size)


if __name__ == "__main__":
    main()
