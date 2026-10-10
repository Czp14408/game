"""Escaped local reports, independent of the generated game bundle."""
import html
import json
import re
from datetime import datetime
from pathlib import Path


def write_report(directory, workbook, *, checked, payload=None, previous=None,
                 warnings=(), edits=None, error=None):
    before = {i['id']: i for i in (previous or {}).get('items', [])}
    after = {i['id']: i for i in (payload or {}).get('items', [])}
    changes = {} if payload is None else {
        '新增': sorted(after.keys() - before.keys()),
        '删除': sorted(before.keys() - after.keys()),
        '修改': sorted(i for i in after.keys() & before.keys() if after[i] != before[i])}
    warnings = list(warnings)
    for item in after.values():
        width, height = item['image_size']
        if width and height and width * 2 != height * item['size']:
            warnings.append(f'{item["name"]}：原图 {width}×{height}，建议构图比例 {item["size"]}:2；当前允许导入，请在卡面预览检查裁切与拉伸。')
    status = ('校验失败' if checked else '更新失败，保留上一版') if error else ('校验通过，未更新工程' if checked else '已更新工程')
    report = dict(time=datetime.now().astimezone().isoformat(timespec='seconds'),
                  status=status, workbook=str(Path(workbook).resolve()),
                  version=(payload or {}).get('content_version'), changes=changes,
                  warnings=list(warnings), error=str(error) if error else None,
                  error_cells=[{'sheet': s, 'cell': c} for s, c in re.findall(r'([^\s：:，,;；!]+)!([A-Z]+[0-9]+)', str(error or ''))],
                  auto_fill=edits or {}, items=(payload or {}).get('items', []))
    e = lambda value: html.escape(str(value), quote=True)
    parts = [f'<h1>{e(status)}</h1><p>{e(report["time"])}</p>', f'<p>工作簿：{e(report["workbook"])}</p>']
    if error:
        parts += [f'<h2>需要修正</h2><pre>{e(error)}</pre>', '<p>展示本次遇到的首个错误；修正后重新运行，继续校验。</p>']
    else:
        parts += [f'<p>共 {len(after)} 件启用物品 · 版本 {e(report["version"])}</p>', '<h2>与当前工程的差异</h2>']
        for label, ids in changes.items():
            parts.append(f'<p><b>{label}</b>：{e("、".join(ids) or "无")}</p>')
        parts.append('<h2>物品检查清单</h2><table><tr><th>名称 / ID</th><th>尺寸</th><th>单次数值（青铜→钻石）</th><th>多重释放</th><th>素材尺寸</th></tr>')
        for item in after.values():
            names = dict(attack='攻击', shield='护盾', poison='中毒', burn='灼烧', heal='回复')
            effects = '；'.join(f'{names.get(x["type"],x["type"])}: {" / ".join(map(str,x["values"]))}' for x in item['effects'])
            if item.get('growth'):
                effects += '；武器成长: ' + ' / '.join(map(str,item['growth']))
            image_size = ' × '.join(map(str,item['image_size'])) if item['icon'] else '旧物品待补图'
            parts.append('<tr>'+''.join(f'<td>{e(v)}</td>' for v in [item['name']+' / '+item['id'], item['size'], effects or '非战斗物品', ' / '.join(map(str,item['multicast'])), image_size])+'</tr>')
        parts.append('</table>')
    parts.append('<h2>提示</h2><ul>'+''.join(f'<li>{e(w)}</li>' for w in warnings)+'</ul>')
    if edits:
        parts.append(f'<p>模板自动补齐：{e("、".join(edits))}（{"本次未保存" if checked or error else "已保存"}）。</p>')
    preview = Path(workbook).resolve().parent / 'preview_items.cmd'
    parts.append(f'<h2>画面与战斗验收</h2><p>保存关闭 Excel 后，双击 {e(preview)}，搜索物品名称或 ID。入口会重新校验，通过后展示四品质卡面、悬停说明及战斗演示。</p>')
    document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>物品导入验收报告</title><style>body{font:16px "Microsoft YaHei",sans-serif;background:#f2f4f7;color:#243244;max-width:1100px;margin:32px auto;padding:24px}table{border-collapse:collapse;background:white;width:100%}td,th{padding:12px;border:1px solid #ccd5df;text-align:left}pre{white-space:pre-wrap;background:#fff0eb;padding:16px}h2{margin-top:30px}</style>'+''.join(parts)+'</html>'
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    (directory/'latest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    target = directory/'latest.html'
    target.write_text(document,encoding='utf-8')
    return target
