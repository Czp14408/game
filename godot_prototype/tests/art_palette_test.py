import importlib.util
import json
from pathlib import Path
import struct
import unittest
import zlib

spec = importlib.util.spec_from_file_location('art_palette', Path(__file__).parents[1] / 'tools/art_palette.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))


def png_rgba(rgba):
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\0' + bytes(rgba))) + chunk(b'IEND', b''))


class ArtPaletteTest(unittest.TestCase):
    def test_palette_has_128_unique_colors(self):
        colors = json.loads(tool.PALETTE.read_text())['colors']
        self.assertEqual(len(colors), 128)
        self.assertEqual(len(set(colors)), 128)

    def test_opaque_approved_color(self):
        self.assertEqual(tool.check_image('', png_rgba([24, 92, 58, 255]), False), '128 色校验通过')

    def test_off_palette_and_partial_alpha_rejected(self):
        for rgba in [[1, 2, 3, 255], [24, 92, 58, 128]]:
            with self.subTest(rgba=rgba), self.assertRaises(ValueError):
                tool.check_image('', png_rgba(rgba), False)

    def test_fully_transparent_pixels_are_ignored(self):
        self.assertEqual(tool.check_image('', png_rgba([1, 2, 3, 0]), False), '128 色校验通过')

    def test_indexed_four_bit_png(self):
        image = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 1, 4, 3, 0, 0, 0))
                 + chunk(b'PLTE', bytes([24, 92, 58, 1, 2, 3])) + chunk(b'tRNS', bytes([255, 0]))
                 + chunk(b'IDAT', zlib.compress(bytes([0, 0x01]))) + chunk(b'IEND', b''))
        self.assertEqual(tool.check_image('', image, False), '128 色校验通过')

    def test_legacy_exemption_is_pinned_to_exact_bytes(self):
        path = 'assets/items/icons/poison_vial.png'
        data = (tool.PROJECT / path).read_bytes()
        self.assertEqual(tool.check_image(path, data), '旧素材原图例外')
        with self.assertRaises(ValueError):
            tool.check_image(path, data + b'changed')

    def test_attribute_text_contrast(self):
        def luminance(value):
            rgb = [int(value[i:i+2], 16) / 255 for i in (0, 2, 4)]
            linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
            return sum(v * w for v, w in zip(linear, [.2126, .7152, .0722]))
        for fill, ink in [('b53240','f3f6fa'), ('f2cc60','10151f'), ('185c3a','f3f6fa'),
                          ('d97624','10151f'), ('56c675','10151f')]:
            a, b = sorted([luminance(fill), luminance(ink)])
            self.assertGreaterEqual((b+.05)/(a+.05), 4.5)


if __name__ == '__main__':
    unittest.main()
