"""Export generated blank UI sources to cropped Godot textures and measured metadata.

No UI contents are painted here. Source PNGs remain intact; exports only trim
transparent margins using sustained alpha occupancy and scale by nearest neighbour.

This generator produces TWO manifests:
  - manifest.json : asset geometry (texture size, source crop, inner cavity,
                    nine-patch margins, center alpha, control kind).
                    Pure geometry, no page positions.
  - layout.json   : page coordinates on the 1280x690 design canvas for each
                    panel, plus named sub-regions within each panel
                    (e.g. status_panel's stats / battle_bar / skills sections).
                    The access layer (SystemSkin) reads both; pages never
                    hardcode coordinates.

Why two files: asset geometry is intrinsic to the source art and changes when
the art changes; page layout is a design decision and changes when the layout
changes. Keeping them separate means swapping art doesn't require touching
layout, and vice versa.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/ui/system_components_v1'
WIDTHS = {'inventory_tray': 1152, 'status_panel': 1152,
          'information_panel': 1120, 'tooltip_panel': 360,
          'context_menu': 200, 'minimap_frame': 176, 'battle_statistics': 720}

# ---------------------------------------------------------------------------
# Page layout on the 1280x690 design canvas (1280x720 minus the top 30px status
# bar owned by AppRoot). All coordinates are design-canvas coordinates with the
# origin at the top-left of the page region.
#
# Layout decisions (per 游戏主界面与交互调整方案.md §1, §2):
#   - World scene fills the canvas; overlays sit on top.
#   - minimap_frame: top-right corner (always visible on world scene).
#   - inventory_tray: bottom-edge, horizontally centred (B toggle).
#   - status_panel: directly above inventory_tray (Tab toggle, paired with
#     inventory_tray per the doc).
#   - information_panel: full info page (M key), centred on canvas.
#   - tooltip_panel / context_menu: floating overlays; the rect here is a
#     default size, the page repositions them at runtime.
#   - battle_statistics: battle page drawer, bottom-right.
# ---------------------------------------------------------------------------
DESIGN_W, DESIGN_H = 1280, 690

LAYOUT = {
    'design': [DESIGN_W, DESIGN_H],
    'panels': {
        # Top-right minimap frame: 12px from edges.
        'minimap_frame': {
            'rect': [DESIGN_W - 176 - 12, 12, 176, 174],
            'regions': {
                # Inner area where the actual minimap content renders.
                # The frame is decorative; the map is clipped to this rect.
                'map_view': [24, 24, 128, 126],
            },
        },
        # Bottom inventory tray: 8px from bottom edge, centred horizontally.
        'inventory_tray': {
            'rect': [(DESIGN_W - 1152) // 2, DESIGN_H - 153 - 8, 1152, 153],
            'regions': {
                # Inner cavity holds the 10 slot grid; tray inner is at 20,14.
                'slots': [20, 14, 1112, 125],
            },
        },
        # Status bar directly above inventory_tray (6px gap).
        'status_panel': {
            'rect': [(DESIGN_W - 1152) // 2,
                     DESIGN_H - 153 - 8 - 164 - 6, 1152, 164],
            'regions': {
                # Three sections inside the 1122x134 inner cavity (15px margins):
                # left: HP/gold/chances (200 wide)
                # middle: 10-slot battle bar (760 wide; 10x76px)
                # right: skill bar (162 wide; allows overflow arrows)
                'stats': [15, 15, 200, 134],
                'battle_bar': [220, 15, 760, 134],
                'skills': [985, 15, 152, 134],
            },
        },
        # Information page: centred on canvas (M key).
        'information_panel': {
            'rect': [(DESIGN_W - 1120) // 2, (DESIGN_H - 581) // 2, 1120, 581],
            'regions': {
                # Inner cavity 1016x477 (52px margins). Split left/right.
                'world_map': [52, 52, 600, 477],   # left: node graph
                'quests': [657, 52, 407, 477],     # right: quests / intel
            },
        },
        # Tooltip: floating; default size only.
        'tooltip_panel': {
            'rect': [0, 0, 360, 281],
            'regions': {
                'content': [25, 25, 310, 231],
            },
        },
        # Context menu: floating; default size only.
        'context_menu': {
            'rect': [0, 0, 200, 102],
            'regions': {
                'items': [9, 9, 182, 84],
            },
        },
        # Battle statistics drawer: bottom-right of battle page canvas.
        'battle_statistics': {
            'rect': [DESIGN_W - 720 - 16, DESIGN_H - 316 - 8, 720, 316],
            'regions': {
                'stats': [28, 28, 664, 130],
                'events': [28, 162, 664, 126],
            },
        },
    },
}


def export():
    records = {}
    for name, width in WIDTHS.items():
        source = Image.open(BASE / 'source' / (name + '.png')).convert('RGBA')
        pixels = np.asarray(source)
        alpha = pixels[:, :, 3]
        visible = alpha > 24
        # Sustained occupancy excludes isolated generation flecks from crop bounds.
        if name == 'minimap_frame':
            xs = np.where(visible.sum(axis=0) > visible.sum(axis=0).max() * .08)[0]
            ys = np.where(visible.sum(axis=1) > visible.sum(axis=1).max() * .08)[0]
        else:
            xs = np.where(visible.sum(axis=0) > visible.sum(axis=0).max() * .5)[0]
            ys = np.where(visible.sum(axis=1) > visible.sum(axis=1).max() * .5)[0]
        box = (int(xs[0]), int(ys[0]), int(xs[-1]) + 1, int(ys[-1]) + 1)
        cropped = source.crop(box)
        height = round(cropped.height * width / cropped.width)
        texture = cropped.resize((width, height), Image.Resampling.NEAREST)
        texture.save(BASE / (name + '.png'))
        rgba = np.asarray(texture)
        # Measure uniform central cavity, keeping conservative padding for corners.
        if name != 'minimap_frame':
            rgb = rgba[:, :, :3].astype(float)
            center = rgb[height//2-3:height//2+4, width//2-3:width//2+4]
            base = np.median(center.reshape(-1, 3), axis=0)
            same = (np.abs(rgb-base).sum(axis=2) < 65) & (rgba[:, :, 3] > 0)
            x = np.where(same.mean(axis=0) > .65)[0]
            y = np.where(same.mean(axis=1) > .65)[0]
            pad = max(8, round(min(width,height)*.09))
            inner = [max(pad,int(x[0])), max(pad,int(y[0])),
                     min(width-pad,int(x[-1])+1), min(height-pad,int(y[-1])+1)]
            margins = [inner[0],inner[1],width-inner[2],height-inner[3]]
            inner = [inner[0],inner[1],inner[2]-inner[0],inner[3]-inner[1]]
            assert inner[2] > 0 and inner[3] > 0
        else:
            inner, margins = None, None
        records[name] = {'texture': name+'.png', 'source': 'source/'+name+'.png',
            'source_crop': list(box), 'size': [width,height], 'inner': inner,
            'nine_patch_margins_ltrb': margins,
            'center_alpha': int(rgba[height//2,width//2,3]),
            'control': 'TextureRect' if name=='minimap_frame' else 'NinePatchRect'}
        assert source.getpixel((0,0))[3] == 0
    manifest = {'version': 1, 'filter': 'nearest', 'mipmaps': False,
                'status': 'connected_via_system_skin',
                'assets': records}
    (BASE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

    # Layout manifest: page coordinates for each panel + named sub-regions.
    # Pages read this through SystemSkin.rect() / SystemSkin.region().
    (BASE/'layout.json').write_text(json.dumps(LAYOUT,ensure_ascii=False,indent=2),encoding='utf-8')

    print(json.dumps({k: v['size'] for k, v in records.items()}))
    print('layout.json written with %d panels' % len(LAYOUT['panels']))


if __name__ == '__main__':
    export()
