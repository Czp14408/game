"""Deterministic item image conversion and a local Tk preview/export window."""
import argparse
import io
import json
import re
from pathlib import Path

from PIL import Image, ImageOps
from art_palette import PALETTE, PROJECT, check_image

SIZES = {'小物品': (128, 256), '中物品': (256, 256), '大物品': (384, 256)}
BACKGROUND = '#101B28'


def load_image(path):
    with Image.open(path) as image:
        if getattr(image, 'n_frames', 1) != 1:
            raise ValueError('请使用单帧图片，动画图片不支持。')
        return ImageOps.exif_transpose(image).convert('RGBA')


def normalize(image, size, *, fit='contain', transparent=False):
    if size not in SIZES.values() or fit not in ('contain', 'cover'):
        raise ValueError('未知尺寸或构图方式。')
    colors = [tuple(bytes.fromhex(c.lstrip('#'))) for c in json.loads(PALETTE.read_text(encoding='utf-8'))['colors']]
    image = image.convert('RGBA')
    if not transparent:
        base = Image.new('RGBA', image.size, BACKGROUND)
        base.alpha_composite(image)
        image = base
    ratio = (min if fit == 'contain' else max)(size[0]/image.width, size[1]/image.height)
    scaled = image.resize((max(1, round(image.width*ratio)), max(1, round(image.height*ratio))), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', size, (0, 0, 0, 0) if transparent else BACKGROUND)
    # Paste without a mask preserves source alpha for subsequent binary conversion.
    canvas.paste(scaled, ((size[0]-scaled.width)//2, (size[1]-scaled.height)//2))
    palette = Image.new('P', (1, 1))
    palette.putpalette([channel for color in colors for channel in color] + list(colors[0])*(256-len(colors)))
    result = canvas.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE).convert('RGBA')
    if transparent:
        result.putalpha(canvas.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    data = io.BytesIO()
    result.save(data, format='PNG', interlace=0)
    check_image('', data.getvalue(), allow_legacy=False)
    return result, data.getvalue()


def export_image(data, target, source):
    target, source = Path(target), Path(source)
    if target.resolve() == source.resolve():
        raise ValueError('不能覆盖原图，请选择新的输出文件。')
    if target.suffix.lower() != '.png':
        raise ValueError('输出文件必须为 .png。')
    check_image('', data, allow_legacy=False)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive create protects both original art and previously exported assets.
    with target.open('xb') as stream:
        try:
            stream.write(data)
        except BaseException:
            stream.close()
            target.unlink(missing_ok=True)
            raise
    return target


def gui():
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    from PIL import ImageTk

    root = tk.Tk()
    root.title('物品图片规范工具 · 128 色')
    root.geometry('980x780')
    root.minsize(900, 720)
    root.option_add('*Font', ('Microsoft YaHei', 10))
    frame = ttk.Frame(root, padding=18)
    frame.pack(fill='both', expand=True)
    source = None
    original = converted = data = None
    photos = []
    size_var = tk.StringVar(value='小物品')
    fit_var = tk.StringVar(value='保留完整图片，补背景')
    alpha_var = tk.BooleanVar(value=False)
    id_var = tk.StringVar(value='shield_dagger')
    status = tk.StringVar(value='请选择原图。原图保留，导出文件不会覆盖已有图片。')
    ttk.Label(frame, text='选择原图 → 调整规格 → 查看对比 → 导出 PNG', font=('Microsoft YaHei', 15, 'bold')).pack(anchor='w')
    settings = ttk.Frame(frame)
    settings.pack(fill='x', pady=12)
    ttk.Label(settings, text='物品尺寸').grid(row=0, column=0, padx=5)
    size_box = ttk.Combobox(settings, textvariable=size_var, values=list(SIZES), state='readonly', width=9)
    size_box.grid(row=0, column=1)
    fit_box = ttk.Combobox(settings, textvariable=fit_var, values=['保留完整图片，补背景', '填满画布，居中裁切'], state='readonly', width=24)
    fit_box.grid(row=0, column=2, padx=10)
    ttk.Checkbutton(settings, text='保留透明（透明度二值化）', variable=alpha_var, command=lambda: refresh()).grid(row=0, column=3)
    views = ttk.Frame(frame)
    views.pack(fill='both', expand=True)
    canvases = []
    for label in ['原图（仅显示缩略图）', '规范后（最近邻预览）']:
        pane = ttk.LabelFrame(views, text=label, padding=5)
        pane.pack(side='left', fill='both', expand=True, padx=5)
        canvas = tk.Canvas(pane, width=420, height=410, bg='#243346', highlightthickness=0)
        canvas.pack(fill='both', expand=True)
        canvases.append(canvas)
    ttk.Label(frame, textvariable=status, wraplength=910).pack(anchor='w', pady=12)
    ttk.Label(frame, text='默认补背景不拉伸；裁切可能切掉边缘。限色会改变部分颜色，请检查轮廓与细节。').pack(anchor='w')
    actions = ttk.Frame(frame)
    actions.pack(fill='x', pady=12)
    ttk.Label(actions, text='物品 ID').pack(side='left')
    ttk.Entry(actions, textvariable=id_var, width=24).pack(side='left', padx=8)

    def draw(canvas, image):
        width, height = max(1, canvas.winfo_width()), max(1, canvas.winfo_height())
        ratio = min((width-20)/image.width, (height-20)/image.height)
        shown = image.resize((max(1, round(image.width*ratio)), max(1, round(image.height*ratio))), Image.Resampling.NEAREST)
        backing = Image.new('RGBA', shown.size)
        for y in range(0, shown.height, 12):
            for x in range(0, shown.width, 12):
                backing.paste('#42536B' if (x//12+y//12)%2 else '#243346', (x,y,min(x+12,shown.width),min(y+12,shown.height)))
        backing.alpha_composite(shown)
        photo = ImageTk.PhotoImage(backing)
        photos.append(photo)
        canvas.delete('all')
        canvas.create_image(width//2, height//2, image=photo)

    def refresh(event=None):
        nonlocal converted, data
        if original is None:
            return
        try:
            converted, data = normalize(original, SIZES[size_var.get()], fit='cover' if fit_var.get().startswith('填满') else 'contain', transparent=alpha_var.get())
            photos.clear()
            draw(canvases[0], original)
            draw(canvases[1], converted)
            used = len({rgba[:3] for _, rgba in converted.getcolors(converted.width*converted.height) if rgba[3]})
            status.set(f'原图：{source}（{original.width}×{original.height}）\n输出：{converted.width}×{converted.height} PNG · 使用 {used} 种项目颜色 · 校验通过')
            export_button.configure(state='normal')
        except Exception as error:
            data = None
            export_button.configure(state='disabled')
            messagebox.showerror('转换失败', str(error), parent=root)

    def choose():
        nonlocal source, original
        selected = filedialog.askopenfilename(parent=root, title='选择物品原图', filetypes=[('物品图片', '*.png *.jpg *.jpeg *.webp *.bmp'), ('所有文件', '*.*')])
        if not selected:
            return
        try:
            image = load_image(selected)
        except Exception as error:
            messagebox.showerror('无法读取图片', str(error), parent=root)
            return
        source, original = Path(selected), image
        if re.fullmatch(r'[a-z][a-z0-9_]*', source.stem):
            id_var.set(source.stem)
        refresh()

    def save():
        if data is None:
            return
        iid = id_var.get().strip()
        if not re.fullmatch(r'[a-z][a-z0-9_]*', iid):
            messagebox.showerror('物品 ID 格式', '请使用英文小写开头，后接小写字母、数字或下划线。', parent=root)
            return
        directory = PROJECT/'assets/items/icons'
        target = filedialog.asksaveasfilename(parent=root, title='导出规范图片（已有文件不可覆盖）', initialdir=str(directory), initialfile=iid+'.png', defaultextension='.png', filetypes=[('PNG 图片', '*.png')])
        if not target:
            return
        try:
            exported = export_image(data, target, source)
            try:
                field = exported.resolve().relative_to(PROJECT).as_posix()
            except ValueError:
                field = '图片导出在工程外，请复制到 assets/items/icons 后填写相对路径。'
            messagebox.showinfo('导出完成', f'{exported}\n\nExcel 图标覆盖路径：\n{field}\n\n下一步填写 items.xlsx，运行 update_items.cmd。', parent=root)
        except Exception as error:
            messagebox.showerror('导出失败', f'{error}\n已有文件请改名或先手动备份移走。', parent=root)

    ttk.Button(actions, text='选择原图', command=choose).pack(side='left', padx=8)
    export_button = ttk.Button(actions, text='导出规范 PNG', command=save, state='disabled')
    export_button.pack(side='left', padx=8)
    for box in (size_box, fit_box):
        box.bind('<<ComboboxSelected>>', refresh)
    for canvas in canvases:
        canvas.bind('<Configure>', lambda event: refresh() if original is not None else None)
    root.mainloop()


def main():
    parser = argparse.ArgumentParser(description='规范物品图片；无参数打开对比与导出窗口')
    parser.add_argument('source', nargs='?', type=Path)
    parser.add_argument('--size', choices=['small', 'medium', 'large'], default='small')
    parser.add_argument('--fit', choices=['contain', 'cover'], default='contain')
    parser.add_argument('--transparent', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.source is None:
        gui()
        return 0
    if args.output is None:
        parser.error('命令行转换必须指定 --output，不覆盖原图')
    try:
        size = dict(small=(128,256), medium=(256,256), large=(384,256))[args.size]
        _, data = normalize(load_image(args.source), size, fit=args.fit, transparent=args.transparent)
        export_image(data, args.output, args.source)
        print(f'已导出 {args.output}：{size[0]}×{size[1]}，128 色校验通过')
        return 0
    except (OSError, ValueError) as error:
        print(f'转换失败：{error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
