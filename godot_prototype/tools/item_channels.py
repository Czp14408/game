"""Validate non-shop acquisition rules against existing engine entry points."""
import re


def compile_rule(row, n, enabled_ids, project, *, text, number, fail, qualities):
    iid = text(row, 'A', '获取渠道', n)
    if iid not in enabled_ids:
        fail('获取渠道', n, 'A', '渠道引用了不存在或禁用的物品')
    kind = text(row, 'B', '获取渠道', n)
    if kind not in ('drop', 'event', 'quest'):
        fail('获取渠道', n, 'B', '支持 shop/drop/event/quest，其他渠道尚未实现')
    pool = text(row, 'C', '获取渠道', n)
    if kind == 'drop':
        valid = {p.stem for p in (project/'data/enemies').glob('*.tres')}
    elif kind == 'event':
        valid = {'material_small', 'supply_small'}
    else:
        valid = set()
        for path in (project/'data/worlds').glob('*.tres'):
            valid.update(re.findall(r'quest_id = &"([^"]+)"', path.read_text(encoding='utf-8')))
    if pool not in valid:
        fail('获取渠道', n, 'C', f'{kind} 获取入口不存在：{pool}')
    low, high = text(row,'E','获取渠道',n), text(row,'F','获取渠道',n)
    if low not in qualities or high not in qualities or qualities.index(low) > qualities.index(high):
        fail('获取渠道', n, 'E', '品质范围无效')
    return dict(item=iid, type=kind, pool=pool, weight=number(row,'D','获取渠道',n,0.000001),
                min_quality=qualities.index(low), max_quality=qualities.index(high))
