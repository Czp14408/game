"""Validate the item workbook and publish a deterministic, separately owned content bundle.

Uses only Python's standard library. Legacy build_content.gd never writes this directory.
"""
import argparse
import copy
import io
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from xml.dom import minidom

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_palette import check_image
from item_import_report import write_report
from item_channels import compile_rule
import item_special

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT.parent / 'content/items.xlsx'
OUTPUT = PROJECT / 'data/generated_items'
QUALITIES = ['青铜', '白银', '黄金', '钻石']
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
SUPPORTED = {'weapon': ('attack', 'attack'), 'poison': ('apply_poison', 'poison'),
             'burn': ('apply_burn', 'burn'), 'shield': ('shield', 'shield'), 'heal': ('heal', 'heal')}
TEMPLATES = {'tpl_attack': 'weapon', 'tpl_poison': 'poison', 'tpl_burn': 'burn',
             'tpl_shield': 'shield', 'tpl_heal': 'heal', 'tpl_growth_attack': 'weapon'}
TEMPLATES.update({'tpl_'+category:category for category in sorted(item_special.SPECIAL)})


class InvalidContent(Exception):
    pass


def fail(sheet, row, col, reason):
    raise InvalidContent(f'{sheet}!{col}{row}: {reason}')


def read_workbook(path):
    with zipfile.ZipFile(path) as archive:
        shared = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            shared = [''.join(e.itertext()) for e in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        relationships = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        targets = {e.attrib['Id']: e.attrib['Target'] for e in relationships}
        sheets = {}
        for entry in ET.fromstring(archive.read('xl/workbook.xml')).findall('s:sheets/s:sheet', NS):
            rid = entry.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']
            target = targets[rid]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            cells = {}
            for cell in ET.fromstring(archive.read(target)).findall('s:sheetData/s:row/s:c', NS):
                address = cell.attrib['r']
                if cell.find('s:f', NS) is not None:
                    cells[address] = {'formula': True}
                    continue
                value = cell.find('s:v', NS)
                text = value.text if value is not None else ''
                if cell.attrib.get('t') == 's':
                    text = shared[int(text)]
                elif cell.attrib.get('t') == 'inlineStr':
                    inline = cell.find('s:is', NS)
                    text = ''.join(inline.itertext()) if inline is not None else ''
                cells[address] = text or ''
            sheets[entry.attrib['name']] = cells
        return sheets


def rows(cells):
    numbers = sorted({int(re.search(r'\d+$', k)[0]) for k in cells})
    return [(n, {re.sub(r'\d+$', '', k): v for k, v in cells.items() if k.endswith(str(n)) and int(re.search(r'\d+$', k)[0]) == n})
            for n in numbers if n >= 5 and cells.get(f'A{n}', '') != '']


def text(row, col, sheet, n, required=True):
    value = row.get(col, '')
    if not isinstance(value, str):
        fail(sheet, n, col, '请填写实际值，不使用公式或公式缓存')
    value = value.strip()
    if required and not value:
        fail(sheet, n, col, '必填项为空')
    return value


def number(row, col, sheet, n, minimum=0, integer=False):
    value = text(row, col, sheet, n)
    try:
        result = float(value)
    except ValueError:
        fail(sheet, n, col, '必须填写数字')
    if not math.isfinite(result) or result < minimum or (integer and result != int(result)):
        fail(sheet, n, col, f'必须是至少 {minimum} 的有效' + ('整数' if integer else '数值'))
    return int(result) if integer else result


def stable(value, sheet, n, col):
    if not re.fullmatch(r'[a-z][a-z0-9_]*', value):
        fail(sheet, n, col, 'ID 须以小写字母开头，仅含小写字母、数字和下划线')
    return value


def expand_templates(source):
    """Append supported basic effects from value rows; preserve existing effect snapshots."""
    sheets = copy.deepcopy(source)
    edits = {}
    def put(sheet, cell, value):
        sheets[sheet][cell] = value
        edits.setdefault(sheet, {})[cell] = value
    by_attribute = {attribute: (category, action) for category, (action, attribute) in SUPPORTED.items()}
    for n, item in rows(sheets['物品总表']):
        if item.get('J') != '是' or item.get('G') == 'custom':
            continue
        template = text(item, 'G', '物品总表', n)
        if template not in TEMPLATES:
            fail('物品总表', n, 'G', '该模板机制尚未接入')
        if number(item, 'H', '物品总表', n, 1, True) != 1:
            fail('物品总表', n, 'H', '该模板只支持版本 1；已有快照不会自动升级')
        category = TEMPLATES[template]
        if item.get('C') != category:
            fail('物品总表', n, 'C', f'{template} 的类别须为 {category}')
        iid = item['A']
        configured = [(rn,r) for rn,r in rows(sheets['效果配置']) if r.get('A') == iid]
        values = [(rn,r) for rn,r in rows(sheets['效果数值']) if r.get('A') == iid]
        if not values:
            fail('物品总表', n, 'A', '在效果数值填写物品 ID 和四档数值')
        if category in item_special.SPECIAL:
            item_special.expand(sheets,item,configured,values,put,rows,fail)
            continue
        if template == 'tpl_growth_attack':
            for eid, attribute, order in [('growth','growth',1), ('attack','attack',2)]:
                matching = [(vn,v) for vn,v in values if v.get('B') == eid or (not v.get('B') and v.get('C') == attribute)]
                if len(matching) != 1:
                    fail('物品总表', n, 'A', '成长攻击模板须分别填写 growth 和 attack 两行数值')
                vn, value = matching[0]
                if not value.get('B'): put('效果数值', f'B{vn}', eid)
                if not value.get('C'): put('效果数值', f'C{vn}', attribute)
                if any(r.get('B') == eid for _,r in configured): continue
                en = max([rn for rn,_ in rows(sheets['效果配置'])] + [4]) + 1
                fields = [iid,eid,str(order),'use_self','self',
                          'increase_attribute' if order == 1 else 'attack',
                          'own_battle_bar' if order == 1 else 'enemy',
                          'weapon' if order == 1 else '', '是' if order == 1 else '否',
                          'attack','battle' if order == 1 else 'instant',
                          'quality_parameter' if order == 1 else 'current_attribute',attribute,
                          f'由 {template} v1 创建时复制；后续独立编辑']
                record = dict(zip('ABCDEFGHIJKLMN', fields))
                for col,val in record.items(): put('效果配置', f'{col}{en}', val)
                configured.append((en,record))
            continue
        for vn, value in values:
            eid, attribute = value.get('B',''), value.get('C','')
            match = next((r for _,r in configured if r.get('B') == eid and eid), None)
            if match is not None:
                continue
            if not configured:
                action, expected_attribute = SUPPORTED[category]
                if (eid and eid != action) or (attribute and attribute != expected_attribute):
                    fail('效果数值', vn, 'C', '第一条效果必须对应所选基础模板')
                eid, attribute = action, expected_attribute
            else:
                if attribute not in by_attribute:
                    fail('效果数值', vn, 'C', '新增基础属性须填 attack/shield/poison/burn/heal')
                _, action = by_attribute[attribute]
                eid = eid or action
            if not value.get('B'): put('效果数值', f'B{vn}', eid)
            if not value.get('C'): put('效果数值', f'C{vn}', attribute)
            effect_category, action = by_attribute[attribute]
            order = max([number(r,'C','效果配置',rn,1,True) for rn,r in configured] + [0]) + 1
            en = max([rn for rn,_ in rows(sheets['效果配置'])] + [4]) + 1
            own = attribute in ['shield','heal']
            source_kind = 'current_attribute' if order == 1 and category == 'weapon' else 'quality_parameter'
            fields = [iid, eid, str(order), 'use_self', 'self', action, 'self' if own else 'enemy', '',
                      '是' if own else '否', attribute, 'instant', source_kind, attribute,
                      f'由 {template} v1 创建时复制；后续独立编辑']
            record = dict(zip('ABCDEFGHIJKLMN', fields))
            for col, value in record.items(): put('效果配置', f'{col}{en}', value)
            configured.append((en, record))
    return sheets, edits


def patch_workbook_bytes(original, edits, validations=None):
    """Patch only changed OOXML parts, retaining styles, panes, validation and cached formulas."""
    validations = validations or {}
    with zipfile.ZipFile(io.BytesIO(original)) as archive:
        infos = archive.infolist()
        files = {info.filename: archive.read(info.filename) for info in infos}
    rels = ET.fromstring(files['xl/_rels/workbook.xml.rels'])
    targets = {e.attrib['Id']: e.attrib['Target'] for e in rels}
    for sheet in ET.fromstring(files['xl/workbook.xml']).findall('s:sheets/s:sheet', NS):
        name = sheet.attrib['name']
        if name not in edits and name not in validations:
            continue
        rid = sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']
        target = targets[rid]
        path = target.lstrip('/') if target.startswith('/') else 'xl/' + target
        doc = minidom.parseString(files[path])
        data = doc.getElementsByTagNameNS(NS['s'], 'sheetData')[0]
        for address, value in edits.get(name, {}).items():
            rn = int(re.search(r'\d+$', address)[0])
            existing_rows = list(data.getElementsByTagNameNS(NS['s'], 'row'))
            row = next((r for r in existing_rows if r.getAttribute('r') == str(rn)), None)
            if row is None:
                row = doc.createElementNS(NS['s'], (doc.documentElement.prefix + ':' if doc.documentElement.prefix else '') + 'row')
                row.setAttribute('r', str(rn))
                prior = [r for r in existing_rows if int(r.getAttribute('r')) < rn]
                if prior:
                    previous = prior[-1]
                    for key in ['ht', 'customHeight', 's', 'customFormat']:
                        if previous.hasAttribute(key):
                            row.setAttribute(key, previous.getAttribute(key))
                later = next((r for r in existing_rows if int(r.getAttribute('r')) > rn), None)
                data.insertBefore(row, later)
            cells = list(row.getElementsByTagNameNS(NS['s'], 'c'))
            cell = next((c for c in cells if c.getAttribute('r') == address), None)
            if cell is None:
                cell = doc.createElementNS(NS['s'], (doc.documentElement.prefix + ':' if doc.documentElement.prefix else '') + 'c')
                cell.setAttribute('r', address)
                col = re.sub(r'\d+$', '', address)
                for previous in reversed(existing_rows):
                    if int(previous.getAttribute('r')) >= rn:
                        continue
                    prior_cell = next((c for c in previous.getElementsByTagNameNS(NS['s'], 'c')
                                       if re.sub(r'\d+$', '', c.getAttribute('r')) == col), None)
                    if prior_cell is not None and prior_cell.hasAttribute('s'):
                        cell.setAttribute('s', prior_cell.getAttribute('s'))
                        break
                def order(c):
                    key = re.sub(r'\d+$', '', c.getAttribute('r'))
                    return (len(key), key)
                later = next((c for c in cells if order(c) > (len(col), col)), None)
                row.insertBefore(cell, later)
            while cell.firstChild:
                cell.removeChild(cell.firstChild)
            prefix = doc.documentElement.prefix + ':' if doc.documentElement.prefix else ''
            if isinstance(value,(int,float)) and not isinstance(value,bool):
                cell.setAttribute('t','n')
                numeric = doc.createElementNS(NS['s'],prefix+'v')
                numeric.appendChild(doc.createTextNode(str(value)))
                cell.appendChild(numeric)
                continue
            cell.setAttribute('t', 'inlineStr')
            inline = doc.createElementNS(NS['s'], prefix + 'is')
            text_node = doc.createElementNS(NS['s'], prefix + 't')
            text_node.appendChild(doc.createTextNode(str(value)))
            inline.appendChild(text_node)
            cell.appendChild(inline)
        dimensions = doc.getElementsByTagNameNS(NS['s'], 'dimension')
        if dimensions and edits.get(name):
            bounds = re.findall(r'([A-Z]+)(\d+)', dimensions[0].getAttribute('ref'))
            bounds += [re.fullmatch(r'([A-Z]+)(\d+)', key).groups() for key in edits[name]]
            max_col = max((col for col, _ in bounds), key=lambda col: (len(col), col))
            max_row = max(int(row) for _, row in bounds)
            dimensions[0].setAttribute('ref', f'A1:{max_col}{max_row}')
        for address, values in validations.get(name, {}).items():
            rules = doc.getElementsByTagNameNS(NS['s'], 'dataValidation')
            rule = next((r for r in rules if r.getAttribute('sqref') == address), None)
            if rule is None:
                raise InvalidContent(f'{name}: 找不到需保留并扩展的下拉范围 {address}')
            formula = rule.getElementsByTagNameNS(NS['s'], 'formula1')[0]
            while formula.firstChild:
                formula.removeChild(formula.firstChild)
            formula.appendChild(doc.createTextNode('"' + ','.join(values) + '"'))
        files[path] = doc.toxml(encoding='UTF-8')
    result = io.BytesIO()
    with zipfile.ZipFile(result, 'w') as archive:
        for info in infos:
            archive.writestr(info, files[info.filename])
    return result.getvalue()


def replace_workbook(path, data):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.items-workbook-', delete=False) as out:
            temporary = Path(out.name)
            out.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def _validate_icon(image, icon, n):
    if len(image) < 33 or image[:8] != b'\x89PNG\r\n\x1a\n' or image[12:16] != b'IHDR':
        fail('物品总表', n, 'I', '图片不是有效 PNG 文件头')
    width, height = struct.unpack('>II', image[16:24])
    if not width or not height: fail('物品总表', n, 'I', '图片宽高必须大于零')
    try: check_image(icon, image)
    except (ValueError, OSError) as error: fail('物品总表', n, 'I', str(error))
    return width,height


def compile_content(sheets, project=PROJECT, allow_migration=False):
    for name in ['物品总表', '品质属性', '效果配置', '效果数值', '获取渠道', '公共字典']:
        if name not in sheets:
            raise InvalidContent(f'缺少工作表：{name}')
    headers = {'物品总表': {'A':'物品ID','C':'类别','J':'启用'},
               '品质属性': {'A':'物品ID','B':'品质','C':'冷却毫秒','D':'购买价覆盖'},
               '效果配置': {'A':'物品ID','B':'效果ID','D':'触发事件','F':'动作','M':'参数键'},
               '效果数值': {'A':'物品ID','B':'效果ID','C':'参数键','D':'青铜','G':'钻石'},
               '获取渠道': {'A':'物品ID','C':'内容池ID','G':'启用'}}
    if '物品扩展' in sheets: headers['物品扩展']={'A':'物品ID','B':'自身被动'}
    for sheet, columns in headers.items():
        for col, label in columns.items():
            if sheets[sheet].get(col+'4') != label:
                fail(sheet,4,col,f'表头应为 {label}；请勿移动或重命名模板字段')
    tag_labels = {text(r,'B','公共字典',n): text(r,'C','公共字典',n) for n,r in rows(sheets['公共字典']) if r.get('A') == 'TAG'}
    tag_ids = set(tag_labels)
    items = []
    ids = set()
    warnings = []
    for n, row in rows(sheets['物品总表']):
        item_id = stable(text(row, 'A', '物品总表', n), '物品总表', n, 'A')
        if item_id in ids:
            fail('物品总表', n, 'A', '物品 ID 重复')
        ids.add(item_id)
        enabled = text(row, 'J', '物品总表', n)
        if enabled not in ['是', '否']:
            fail('物品总表', n, 'J', '启用须填写 是 或 否')
        if enabled == '否':
            continue
        registry_path = project.parent/'content/migrated-items.json'
        migrated = set(json.loads(registry_path.read_text(encoding='utf-8')).get('ids',[])) if registry_path.exists() else set()
        if (project / f'data/items/{item_id}.tres').exists() and not (allow_migration and item_id in migrated):
            fail('物品总表', n, 'A', '与旧资源同名；须先显式迁移，禁止双重配置源')
        category = text(row, 'C', '物品总表', n)
        if category not in SUPPORTED and category not in item_special.SPECIAL:
            fail('物品总表', n, 'C', '仅支持攻击/中毒/灼烧/护盾/治疗及其基础组合，其他机制须先接入')
        equippable = category not in ('consumable','material')
        if text(row, 'F', '物品总表', n) != ('是' if equippable else '否'):
            fail('物品总表', n, 'F', '战斗物品须可装备；材料与战斗外恢复品不可装备')
        size = number(row, 'E', '物品总表', n, 1, True)
        if size > 3:
            fail('物品总表', n, 'E', '当前工程最大占格为 3')
        template = text(row, 'G', '物品总表', n)
        if template != 'custom' and template not in TEMPLATES:
            fail('物品总表', n, 'G', '该模板尚未接入，不会自动展开或忽略效果')
        version = number(row, 'H', '物品总表', n, 1, True)
        if template != 'custom' and (TEMPLATES[template] != category or version != 1):
            fail('物品总表', n, 'G', '模板类别或版本不匹配')
        tags = [x.strip() for x in text(row, 'D', '物品总表', n).split(',')]
        if any(t not in tag_ids for t in tags) or len(tags) != len(set(tags)):
            fail('物品总表', n, 'D', 'TAG 必须存在于公共字典且不重复，以英文逗号分隔')
        icon = text(row, 'I', '物品总表', n, False)
        missing_legacy_art = item_id in migrated and not icon
        icon = icon or ('' if missing_legacy_art else f'assets/items/icons/{item_id}.png')
        icon_path = (project / icon).resolve()
        if not missing_legacy_art and (not icon_path.is_relative_to(project.resolve()) or not icon.startswith('assets/')):
            fail('物品总表', n, 'I', '图片须使用 assets/ 下的工程相对路径')
        if not missing_legacy_art and not icon_path.is_file():
            fail('物品总表', n, 'I', f'缺少图片：{icon}')
        image = icon_path.read_bytes() if not missing_legacy_art else b''
        if missing_legacy_art:
            width,height=0,0
            warnings.append(f'{item_id} 迁移时无专属图片，保留文字展示；补图后按项目色表校验')
        else:
            width,height=_validate_icon(image,icon,n)
        # Background images remain independent; migrated missing art is explicit.
        qrows = [(rn, r) for rn,r in rows(sheets['品质属性']) if r.get('A') == item_id]
        if len(qrows) != 4 or {r.get('B') for _, r in qrows} != set(QUALITIES):
            fail('物品总表', n, 'A', '品质属性须且仅须包含青铜、白银、黄金、钻石四行')
        cds, prices = [], []
        multicast_by_quality = {}
        for rn, r in qrows:
            cd = number(r, 'C', '品质属性', rn, 100 if equippable else 0, True)
            if cd % 100:
                fail('品质属性', rn, 'C', '冷却须为 100 毫秒整数倍')
            cds.append(cd)
            release = number(r, 'F', '品质属性', rn, 1, True) if r.get('F', '').strip() else 1
            if release > 10 or (not equippable and release != 1):
                fail('品质属性', rn, 'F', '战斗多重释放须为 1–10；非战斗物品须为 1')
            multicast_by_quality[r['B']] = release
            price = text(r, 'D', '品质属性', rn, False)
            prices.append(None if price == '' else number(r, 'D', '品质属性', rn, 0, True))
        if len(set(cds)) != 1 or len(set(prices)) != 1:
            fail('物品总表', n, 'A', '当前引擎冷却/固定价仅支持四档相同；不能静默丢弃差异')
        if not equippable and cds[0]!=0:
            fail('物品总表',n,'A','材料与战斗外恢复品冷却须为 0')
        if not equippable and prices[0] is not None and prices[0]%2:
            fail('物品总表',n,'A','固定购买价须为非负偶数')
        passive=''
        seen_extra=False
        for rn,extra in rows(sheets.get('物品扩展',{})):
            if extra.get('A')!=item_id: continue
            if seen_extra: fail('物品扩展',rn,'A','同物品扩展配置重复')
            seen_extra=True
            passive=text(extra,'B','物品扩展',rn,False)
            if passive not in ('','charge_on_weapon_use') or (passive and not equippable):
                fail('物品扩展',rn,'B','仅支持现有武器使用充能被动，且须为战斗物品')
        if category in item_special.SPECIAL:
            values,effects,heal=item_special.compile_item(sheets,row,n,qrows,rows=rows,number=number,text=text,fail=fail)
            items.append(dict(id=item_id,name=text(row,'B','物品总表',n),category=category,tags=tags,display_tags=[tag_labels[t] for t in tags],size=size,
                              cooldown_ms=cds[0],values=values,effects=effects,growth=[],multicast=[multicast_by_quality[q] for q in QUALITIES],icon=icon,image_size=[width,height],
                              icon_sha256=hashlib.sha256(image).hexdigest(),template=template,template_version=version,
                              equippable=equippable,out_of_combat_heal=heal,fixed_base_price=prices[0] if prices[0] is not None else -1,self_passive=passive))
            continue
        if prices[0] is not None:
            fail('物品总表', n, 'A', '首版战斗物品沿用品质价格表，请留空价格覆盖')
        erows = [(rn,r) for rn,r in rows(sheets['效果配置']) if r.get('A') == item_id]
        growth = []
        growth_rows = [(rn,r) for rn,r in erows if r.get('F') == 'increase_attribute']
        if template == 'tpl_growth_attack' or growth_rows:
            if category != 'weapon' or len(growth_rows) != 1 or len(erows) != 2:
                fail('物品总表',n,'G','成长攻击首版须为一条全体武器成长和一条攻击')
            gn,g = growth_rows[0]
            expected_growth = dict(zip('BCDEFGHIJKLM', ['growth','1','use_self','self','increase_attribute','own_battle_bar','weapon','是','attack','battle','quality_parameter','growth']))
            for col,wanted in expected_growth.items():
                if g.get(col,'') != wanted: fail('效果配置',gn,col,f'成长机制须填 {wanted}')
            matches = [(vn,v) for vn,v in rows(sheets['效果数值']) if v.get('A') == item_id and v.get('B') == 'growth']
            if len(matches) != 1: fail('效果配置',gn,'B','成长须对应唯一一行数值')
            vn,v = matches[0]
            if v.get('C') != 'growth': fail('效果数值',vn,'C','成长参数键须为 growth')
            growth = [float(number(v,c,'效果数值',vn,0,True)) for c in 'DEFG']
            if any(v > 99999 for v in growth): fail('效果数值',vn,'D','成长数值须为 0–99999 整数')
            erows = [(rn,r) for rn,r in erows if r.get('F') != 'increase_attribute']
        maximum = 3 if size == 1 else 5
        if not 1 <= len(erows) <= maximum:
            fail('物品总表', n, 'A', f'该尺寸须有 1–{maximum} 种基础效果')
        erows.sort(key=lambda pair: number(pair[1],'C','效果配置',pair[0],1,True))
        effects, effect_ids, attributes = [], set(), set()
        vrows = [(rn,r) for rn,r in rows(sheets['效果数值']) if r.get('A') == item_id]
        valid_ids = {r.get('B') for _,r in erows} | ({'growth'} if growth else set())
        for vn,value in vrows:
            if value.get('B') not in valid_ids: fail('效果数值',vn,'B','效果 ID 与效果配置不一致')
        for index,(en,effect) in enumerate(erows):
            attribute = text(effect,'J','效果配置',en)
            by_attribute = {v[1]:(k,v[0]) for k,v in SUPPORTED.items()}
            if attribute not in by_attribute:
                fail('效果配置',en,'J','仅支持 attack/shield/poison/burn/heal 基础效果')
            effect_category, action = by_attribute[attribute]
            if index == 0 and effect_category != category:
                fail('效果配置',en,'J','第一条效果须与物品类别一致')
            if attribute in attributes:
                fail('效果配置',en,'J','同一物品的同种基础属性只能配置一次')
            attributes.add(attribute)
            own = attribute in ['shield','heal']
            expected = {'C':str(index+1+(1 if growth else 0)),'D':'use_self','E':'self','F':action,
                        'G':'self' if own else 'enemy','H':'','I':'是' if own else '否',
                        'K':'instant','L':'current_attribute' if index == 0 and category == 'weapon' else 'quality_parameter'}
            for col, expected_value in expected.items():
                if text(effect,col,'效果配置',en,False) != expected_value:
                    fail('效果配置',en,col,f'该基础机制应填 {expected_value or "空白"}，不支持的组合不会被忽略')
            eid = stable(text(effect,'B','效果配置',en),'效果配置',en,'B')
            if eid in effect_ids: fail('效果配置',en,'B','效果 ID 重复')
            effect_ids.add(eid)
            parameter = stable(text(effect,'M','效果配置',en),'效果配置',en,'M')
            matched = [(rn,r) for rn,r in vrows if r.get('B') == eid]
            if len(matched) != 1:
                fail('物品总表',n,'A','每条效果须且仅须对应一行效果数值，效果 ID 须匹配')
            vn,value = matched[0]
            if value.get('C') != parameter: fail('效果数值',vn,'C','参数键与效果配置不一致')
            values = [float(number(value,c,'效果数值',vn,0,True)) for c in 'DEFG']
            for c,amount in zip('DEFG',values):
                if amount > 99999: fail('效果数值',vn,c,'卡面数值须为 0–99999 的整数')
            effects.append(dict(id=eid,type=attribute,values=values,target='self' if own else 'enemy'))
        for vn,value in vrows:
            if value.get('B') not in effect_ids | ({'growth'} if growth else set()): fail('效果数值',vn,'B','效果 ID 与效果配置不一致')
        items.append(dict(id=item_id,name=text(row,'B','物品总表',n),category=category,tags=tags,display_tags=[tag_labels[t] for t in tags],size=size,
                          cooldown_ms=cds[0],values=effects[0]['values'],effects=effects,growth=growth,multicast=[multicast_by_quality[q] for q in QUALITIES],icon=icon,image_size=[width,height],
                          icon_sha256=hashlib.sha256(image).hexdigest(),template=template,template_version=version))
        if passive: items[-1]['self_passive']=passive
    enabled_ids = {i['id'] for i in items}
    for rn,extra in rows(sheets.get('物品扩展',{})):
        if extra.get('A') not in ids: fail('物品扩展',rn,'A','扩展引用了不存在的物品')
    channels = []
    rewards = []
    keys = set()
    items_by_id={item['id']:item for item in items}
    for n,row in rows(sheets['获取渠道']):
        flag = text(row,'G','获取渠道',n)
        if flag not in ['是','否']:
            fail('获取渠道',n,'G','启用须填写 是 或 否')
        if flag == '否':
            continue
        iid = text(row,'A','获取渠道',n)
        if iid not in enabled_ids:
            fail('获取渠道',n,'A','渠道引用了不存在或禁用的物品')
        if text(row,'B','获取渠道',n) != 'shop':
            rule = compile_rule(row,n,enabled_ids,project,text=text,number=number,fail=fail,qualities=QUALITIES)
            if items_by_id[iid].get('fixed_base_price',-1)>=0 and rule['min_quality']!=0:
                fail('获取渠道',n,'E','固定价非战斗物品仅发放青铜，品质范围须包含青铜')
            key=(iid,rule['type'],rule['pool'])
            if key in keys: fail('获取渠道',n,'C','同物品同渠道入口重复')
            keys.add(key)
            rewards.append(rule)
            warnings.append(f'{iid} 已配置 {rule["type"]}：{rule["pool"]}；候选按权重选择，品质在范围内等概率')
            continue
        shop = stable(text(row,'C','获取渠道',n),'获取渠道',n,'C')
        if not (project / f'data/shops/{shop}.tres').is_file():
            fail('获取渠道',n,'C','商店 ID 不存在')
        shop_text = (project / f'data/shops/{shop}.tres').read_text(encoding='utf-8')
        match = re.search(r'quality_weights = PackedFloat64Array\(([^)]+)\)',shop_text)
        if not match:
            fail('获取渠道',n,'C','无法确认该商店品质权重')
        weights = [float(x) for x in match[1].split(',')]
        low,high = text(row,'E','获取渠道',n),text(row,'F','获取渠道',n)
        if low not in QUALITIES or high not in QUALITIES or QUALITIES.index(low)>QUALITIES.index(high):
            fail('获取渠道',n,'E','品质范围无效')
        minimum,maximum=QUALITIES.index(low),QUALITIES.index(high)
        if items_by_id[iid].get('fixed_base_price',-1)>=0 and minimum!=0:
            fail('获取渠道',n,'E','固定价非战斗物品仅出售青铜，品质范围须包含青铜')
        if not any(weights[q]>0 for q in range(minimum,maximum+1)):
            fail('获取渠道',n,'E','物品品质范围与商店概率没有交集')
        key=(iid,shop)
        if key in keys:
            fail('获取渠道',n,'C','同物品同商店渠道重复')
        keys.add(key)
        channels.append(dict(item=iid,shop=shop,weight=number(row,'D','获取渠道',n,0.000001),min_quality=minimum,max_quality=maximum))
        available=[QUALITIES[q] for q in range(minimum,maximum+1) if weights[q]>0]
        if items_by_id[iid].get('fixed_base_price',-1)>=0:available=['青铜']
        warnings.append(f'{iid} 在 {shop} 自然出售品质：{"、".join(available)}；不改变商店原有品质概率')
    for item in items:
        if not any(c['item']==item['id'] for c in channels+rewards):
            warnings.append(f'{item["id"]} 未配置 Excel 启用渠道；'+('迁移前敌人／事件引用仍有效' if item['id'] in migrated else '仅可通过固定预览验证'))
    payload=dict(schema=1,items=sorted(items,key=lambda x:x['id']),shops=sorted(channels,key=lambda x:(x['shop'],x['item'])))
    if (project.parent/'content/migrated-items.json').exists(): payload['item_source']='excel'
    if rewards: payload['channels']=sorted(rewards,key=lambda x:(x['type'],x['pool'],x['item']))
    digest=hashlib.sha256(json.dumps(payload,ensure_ascii=False,sort_keys=True).encode()).hexdigest()[:16]
    payload['content_version']='items-'+digest
    return payload,warnings


def resource(item):
    q = lambda value: json.dumps(value,ensure_ascii=False)
    effects = item['effects']
    event = {'attack':'use_weapon','shield':'use_shield','heal':'heal','burn':'apply_burn','poison':'apply_poison','haste':'','slow':'','freeze':''}
    subs = []
    for index,effect in enumerate(effects):
        subs.append(f'''[sub_resource type="Resource" id="Effect{index}"]
script = ExtResource("2")
effect_type = &{q(effect['type'])}
target_rule = &{q(effect['target'])}
emits_event = &{q('' if effect['type'] == 'attack' and item['category'] != 'weapon' else event[effect['type']])}
tier_values = PackedFloat64Array({', '.join(str(v) for v in effect['values'])})
''')
    return f'''[gd_resource type="Resource" script_class="ItemDef" load_steps={len(effects)+3} format=3]

[ext_resource type="Script" path="res://scripts/data/item_def.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/effect_def.gd" id="2"]

{chr(10).join(subs)}
[resource]
script = ExtResource("1")
definition_id = &{q(item['id'])}
display_name = {q(item['name'])}
category = &{q(item['category'])}
tags = Array[StringName]([{', '.join('&'+q(t) for t in item['tags'])}])
display_tags = PackedStringArray({', '.join(q(t) for t in item['display_tags'])})
size = {item['size']}
cooldown_ms = {item['cooldown_ms']}
tier_values = PackedFloat64Array({', '.join(str(v) for v in item['values'])})
tier_multicast = PackedInt32Array({', '.join(str(v) for v in item['multicast'])})
tier_weapon_growth = PackedFloat64Array({', '.join(str(v) for v in item.get('growth', []))})
icon_path = {q('res://'+item['icon'] if item['icon'] else '')}
self_passive = &{q(item.get('self_passive',''))}
equippable = {str(item.get('equippable',True)).lower()}
out_of_combat_heal = {item.get('out_of_combat_heal',0.0)}
fixed_base_price = {item.get('fixed_base_price',-1)}
effects = Array[ExtResource("2")]([{', '.join(f'SubResource("Effect{index}")' for index in range(len(effects)))}])
'''


def publish(payload, output=OUTPUT):
    output.parent.mkdir(parents=True,exist_ok=True)
    lock = output.with_name('.items-publish.lock')
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise InvalidContent('另一个物品生成正在进行，请稍后重试；异常中断后确认无生成进程再移除 .items-publish.lock')
    os.close(descriptor)
    # Sibling rename avoids mixing generations. The previous complete bundle is recoverable.
    stage=None
    backup=output.with_name('.items-previous')
    try:
        stage=Path(tempfile.mkdtemp(prefix='.items-stage-',dir=output.parent))
        for item in payload['items']:
            (stage/(item['id']+'.tres')).write_text(resource(item),encoding='utf-8',newline='\n')
        (stage/'manifest.json').write_text(json.dumps(payload,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')
        if backup.exists(): shutil.rmtree(backup)
        had_previous=output.exists()
        if had_previous: output.rename(backup)
        try: stage.rename(output)
        except OSError:
            if had_previous: backup.rename(output)
            raise
        if backup.exists(): shutil.rmtree(backup, ignore_errors=True)
    finally:
        if stage is not None and stage.exists(): shutil.rmtree(stage)
        lock.unlink(missing_ok=True)


def main():
    parser=argparse.ArgumentParser(description='校验 Excel 并更新物品内容')
    parser.add_argument('--workbook',type=Path,default=SOURCE)
    parser.add_argument('--check',action='store_true',help='只校验，不生成')
    parser.add_argument('--report-dir',type=Path,help='验收报告目录，默认工作簿旁 reports')
    args=parser.parse_args()
    payload = previous = None
    warnings, edits = [], {}
    def report(error=None):
        try:
            path = write_report(args.report_dir or args.workbook.parent / 'reports', args.workbook,
                                checked=args.check, payload=payload, previous=previous,
                                warnings=warnings, edits=edits, error=error)
            print(f'验收报告：{path.resolve()}')
        except (OSError, ValueError, KeyError, TypeError) as report_error:
            print(f'报告未能保存（不影响本次内容处理结果）：{report_error}', file=sys.stderr)
    import_lock = OUTPUT.with_name('.items-import.lock')
    owns_lock = False
    try:
        if not args.check:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            try:
                descriptor = os.open(import_lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                raise InvalidContent('另一个物品导入正在进行；异常中断后确认无导入进程再移除 .items-import.lock')
            os.close(descriptor)
            owns_lock = True
        original = args.workbook.read_bytes()
        sheets, edits = expand_templates(read_workbook(args.workbook))
        payload,warnings=compile_content(sheets)
        previous=json.loads((OUTPUT/'manifest.json').read_text(encoding='utf-8')) if (OUTPUT/'manifest.json').exists() else {'items':[]}
        before={i['id']:i for i in previous['items']}; after={i['id']:i for i in payload['items']}
        for removed in before.keys()-after.keys():
            if removed in {'scrap_material','recovery_draught'}:
                raise InvalidContent(f'不能移除 {removed}，仍被现有容器及默认掉落规则引用')
            for path in (PROJECT/'data').rglob('*.tres'):
                if 'generated_items' in path.parts or any(p.startswith('.items-') for p in path.parts):
                    continue
                if f'&"{removed}"' in path.read_text(encoding='utf-8'):
                    raise InvalidContent(f'不能移除 {removed}，仍被 {path.relative_to(PROJECT)} 引用')
        for label,ids in [('新增',after.keys()-before.keys()),('删除',before.keys()-after.keys()),('修改',[i for i in after.keys()&before.keys() if after[i]!=before[i]])]:
            print(f'{label}：'+('、'.join(sorted(ids)) or '无'))
        for warning in warnings: print('提示：'+warning)
        if edits:
            print('模板复制：'+('仅预览，不写入；' if args.check else '')+ '、'.join(edits))
        if not args.check:
            changed = patch_workbook_bytes(original, edits) if edits else None
            if changed is not None:
                if args.workbook.read_bytes() != original:
                    raise InvalidContent('工作簿在生成期间被修改，请重新运行')
                backup_dir = args.workbook.parent / 'backups'
                backup_dir.mkdir(exist_ok=True)
                backup = backup_dir / (args.workbook.stem + '-' + hashlib.sha256(original).hexdigest()[:16] + '.xlsx')
                if not backup.exists():
                    backup.write_bytes(original)
                replace_workbook(args.workbook, changed)
            try:
                publish(payload, OUTPUT)
            except Exception:
                if changed is not None:
                    replace_workbook(args.workbook, original)
                raise
        print(f'{"校验通过" if args.check else "生成完成"}：{len(payload["items"])} 件物品，版本 {payload["content_version"]}')
        if not args.check:
            print('画面与战斗验收：双击 content/preview_items.cmd，搜索物品名称或 ID。')
        report()
        return 0
    except (InvalidContent,OSError,zipfile.BadZipFile,ET.ParseError,KeyError,ValueError) as error:
        print(f'生成失败，保留上一版内容：{error}',file=sys.stderr)
        report(error)
        return 1
    finally:
        if owns_lock:
            import_lock.unlink(missing_ok=True)


if __name__=='__main__':
    sys.exit(main())
