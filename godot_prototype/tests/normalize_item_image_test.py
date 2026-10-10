import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import normalize_item_image as tool
from art_palette import check_image


class NormalizeTest(unittest.TestCase):
    def test_all_sizes_pass_strict_palette(self):
        image = Image.new('RGBA', (1024, 1024), (121, 46, 202, 128))
        for size in tool.SIZES.values():
            for fit in ('contain', 'cover'):
                for transparent in (False, True):
                    with self.subTest(size=size, fit=fit, transparent=transparent):
                        result, data = tool.normalize(image, size, fit=fit, transparent=transparent)
                        self.assertEqual(result.size, size)
                        self.assertEqual(check_image('', data, False), '128 色校验通过')
                        self.assertTrue(set(result.getchannel('A').tobytes()) <= {0,255})

    def test_contain_preserves_whole_art_cover_fills(self):
        image = Image.new('RGBA', (100, 100), '#E05263')
        contained, _ = tool.normalize(image, (128,256))
        covered, _ = tool.normalize(image, (128,256), fit='cover')
        self.assertEqual(contained.getpixel((0,0))[:3], (16,27,40))
        self.assertEqual(contained.getpixel((64,128))[:3], (224,82,99))
        self.assertEqual(covered.getpixel((0,0))[:3], (224,82,99))

    def test_transparency_threshold_and_no_source_mutation(self):
        image = Image.new('RGBA', (128,256), '#E05263')
        image.putpixel((0,0), (224,82,99,127))
        image.putpixel((1,0), (224,82,99,128))
        before = image.tobytes()
        result, _ = tool.normalize(image, image.size, transparent=True)
        self.assertEqual(result.getpixel((0,0))[3], 0)
        self.assertEqual(result.getpixel((1,0))[3], 255)
        self.assertEqual(image.tobytes(), before)

    def test_export_protects_source_and_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'original.png'
            Image.new('RGB', (20,20), 'red').save(source)
            before = source.read_bytes()
            _, data = tool.normalize(tool.load_image(source), (128,256))
            with self.assertRaises(ValueError):
                tool.export_image(data, source, source)
            output = Path(folder)/'item.png'
            tool.export_image(data, output, source)
            with self.assertRaises(FileExistsError):
                tool.export_image(data, output, source)
            self.assertEqual(source.read_bytes(), before)
            self.assertEqual(output.read_bytes(), data)

    def test_exif_orientation_is_applied(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'photo.jpg'
            exif = Image.Exif()
            exif[274] = 6
            Image.new('RGB', (20,40)).save(path, exif=exif)
            self.assertEqual(tool.load_image(path).size, (40,20))

    def test_window_select_preview_export(self):
        import tkinter as tk
        from tkinter import ttk
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'sample.png'
            output = Path(folder)/'export.png'
            Image.new('RGB', (1024,1024), '#F2CC60').save(source)
            def visit(widget):
                yield widget
                for child in widget.winfo_children():
                    yield from visit(child)
            def drive(root):
                try:
                    root.update()
                    buttons = {w.cget('text'):w for w in visit(root) if isinstance(w, ttk.Button)}
                    buttons['选择原图'].invoke()
                    root.update()
                    buttons['导出规范 PNG'].invoke()
                    self.assertTrue(output.exists())
                    with Image.open(output) as exported:
                        self.assertEqual(exported.size, (128,256))
                finally:
                    root.destroy()
            with patch.object(tk.Tk, 'mainloop', drive), patch('tkinter.filedialog.askopenfilename', return_value=str(source)), patch('tkinter.filedialog.asksaveasfilename', return_value=str(output)), patch('tkinter.messagebox.showinfo'), patch('tkinter.messagebox.showerror') as error:
                tool.gui()
                error.assert_not_called()


if __name__ == '__main__':
    unittest.main()
