"""Check exported PNG pixels against the versioned project palette (standard library)."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

PROJECT = Path(__file__).resolve().parents[1]
PALETTE = PROJECT / 'assets/palettes/game-128-v1.json'
EXEMPTIONS = PROJECT.parent / 'content/legacy-art-palette-exemptions.json'


def pixels(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('素材必须导出为 PNG')
    position, compressed, palette, transparency = 8, bytearray(), b'', b''
    header = None
    while position + 12 <= len(data):
        length = struct.unpack('>I', data[position:position+4])[0]
        kind = data[position+4:position+8]
        body = data[position+8:position+8+length]
        if len(body) != length:
            raise ValueError('PNG 数据不完整')
        if kind == b'IHDR':
            if length != 13:
                raise ValueError('PNG 图片头长度无效')
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'PLTE': palette = body
        elif kind == b'tRNS': transparency = body
        elif kind == b'IDAT': compressed.extend(body)
        position += length + 12
        if kind == b'IEND': break
    if header is None:
        raise ValueError('PNG 缺少图片头')
    width, height, depth, mode, compression, filtering, interlace = header
    channels = {0:1, 2:3, 3:1, 4:2, 6:4}.get(mode)
    if not channels or depth not in ([1, 2, 4, 8] if mode in [0, 3] else [8]) or interlace or compression or filtering:
        raise ValueError('请导出 8 位 RGB/RGBA 或 1/2/4/8 位索引 PNG，关闭交错扫描')
    stride = (width * channels * depth + 7) // 8
    bpp = max(1, (channels * depth + 7) // 8)
    try:
        raw = zlib.decompress(compressed)
    except zlib.error as error:
        raise ValueError('PNG 像素压缩数据无效') from error
    if len(raw) != height * (stride + 1):
        raise ValueError('PNG 像素长度不匹配')
    previous = bytearray(stride)
    for y in range(height):
        offset = y * (stride + 1)
        method = raw[offset]
        row = bytearray(raw[offset+1:offset+1+stride])
        for i in range(stride):
            left = row[i-bpp] if i >= bpp else 0
            up = previous[i]
            upper_left = previous[i-bpp] if i >= bpp else 0
            estimate = left + up - upper_left
            distances = [abs(estimate-left), abs(estimate-up), abs(estimate-upper_left)]
            paeth = [left, up, upper_left][distances.index(min(distances))]
            if method not in range(5): raise ValueError('PNG 行过滤类型无效')
            predictor = [0, left, up, (left+up)//2, paeth][method]
            row[i] = (row[i] + predictor) & 255
        for x in range(width):
            sample = list(row[x*channels:(x+1)*channels]) if depth == 8 else [(row[x*depth//8] >> (8-depth-(x*depth % 8))) & ((1<<depth)-1)]
            if mode == 3:
                index = sample[0]
                rgb = tuple(palette[index*3:index*3+3])
                if len(rgb) != 3: raise ValueError('PNG 索引颜色缺失')
                alpha = transparency[index] if index < len(transparency) else 255
            elif mode in [0, 4]:
                gray = round(sample[0] * 255 / ((1<<depth)-1))
                rgb, alpha = (gray, gray, gray), sample[1] if mode == 4 else 255
                if mode == 0 and transparency and sample[0] == int.from_bytes(transparency, 'big'): alpha = 0
            else:
                rgb, alpha = tuple(sample[:3]), sample[3] if mode == 6 else 255
                if mode == 2 and transparency and rgb == struct.unpack('>HHH', transparency): alpha = 0
            yield rgb, alpha
        previous = row


def check_image(path, data, allow_legacy=True):
    if allow_legacy and EXEMPTIONS.exists():
        exemptions = json.loads(EXEMPTIONS.read_text(encoding='utf-8'))
        if exemptions.get(path) == hashlib.sha256(data).hexdigest():
            return '旧素材原图例外'
    allowed = {tuple(bytes.fromhex(h.lstrip('#'))) for h in json.loads(PALETTE.read_text())['colors']}
    invalid, partial = set(), False
    for rgb, alpha in pixels(data):
        if alpha == 0: continue
        if alpha != 255: partial = True
        if rgb not in allowed and len(invalid) < 5: invalid.add('#' + bytes(rgb).hex().upper())
    if invalid or partial:
        reason = ('调色板外颜色：' + '、'.join(sorted(invalid))) if invalid else ''
        if partial: reason += '；包含半透明像素，请关闭抗锯齿或使用完全透明'
        raise ValueError('未通过 128 色素材规范：' + reason)
    return '128 色校验通过'


def main():
    parser = argparse.ArgumentParser(description='校验新美术 PNG 的项目 128 色约束')
    parser.add_argument('paths', nargs='+', type=Path)
    args = parser.parse_args()
    failed, found = 0, 0
    for path in args.paths:
        files = sorted(path.rglob('*.png')) if path.is_dir() else [path]
        for image in files:
            found += 1
            try:
                print(f'{image}: {check_image("", image.read_bytes(), False)}')
            except (OSError, ValueError, zlib.error, struct.error) as error:
                failed += 1
                print(f'{image}: {error}')
    return 1 if failed or not found else 0


if __name__ == '__main__':
    raise SystemExit(main())
