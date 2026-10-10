"""Importer contract tests: real workbook, input changes, and failed publish rollback."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('item_import', Path(__file__).parents[1]/'tools/import_items.py')
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class ImportItemsTest(unittest.TestCase):
    def growth_input(self):
        source = copy.deepcopy(self.sheets)
        source['物品总表']['J10'] = '否'
        source['物品总表']['J6'] = '是'
        source['物品总表']['I6'] = 'assets/items/icons/poison_vial.png'
        for rn,row in tool.rows(source['获取渠道']):
            if row.get('A') == 'poison_vial': source['获取渠道'][f'G{rn}'] = '否'
        return source

    def test_growth_template_snapshot_and_auto_fill(self):
        source = self.growth_input()
        item = tool.compile_content(source)[0]['items'][0]
        self.assertEqual(item['growth'], [5,7,10,15])
        self.assertEqual(item['values'], [8,12,18,26])
        self.assertEqual(len(item['effects']), 1)
        self.assertIn('tier_weapon_growth = PackedFloat64Array(5.0, 7.0, 10.0, 15.0)',tool.resource(item))
        for key in list(source['效果配置']):
            if key[1:] in ['6','7']: del source['效果配置'][key]
        source['效果数值']['B6'] = ''
        source['效果数值']['B7'] = ''
        expanded, edits = tool.expand_templates(source)
        self.assertTrue(edits)
        self.assertEqual(tool.compile_content(expanded)[0]['items'][0], item)
        self.assertFalse(tool.expand_templates(expanded)[1])

    def test_growth_rejects_unsupported_rules(self):
        for sheet,cell,value in [('效果配置','I6','否'),('效果配置','K6','permanent'),
                                 ('效果配置','H6','tool'),('效果配置','C7','1'),
                                 ('效果数值','D6','100000'),('效果数值','D6','-1'),
                                 ('效果数值','D6','1.5')]:
            source = self.growth_input()
            source[sheet][cell] = value
            with self.subTest(cell=cell,value=value), self.assertRaises(tool.InvalidContent):
                tool.compile_content(source)

    def setUp(self):
        self.sheets = tool.read_workbook(tool.SOURCE)
        # Most cases isolate one editable item, independent of production catalog size.
        for rn,row in tool.rows(self.sheets['物品总表']):
            if row.get('A')!='poison_vial':self.sheets['物品总表'][f'J{rn}']='否'
        for rn,row in tool.rows(self.sheets['获取渠道']):
            if row.get('A')!='poison_vial':self.sheets['获取渠道'][f'G{rn}']='否'

    def test_real_workbook_and_image(self):
        content, _ = tool.compile_content(self.sheets)
        item = content['items'][0]
        self.assertEqual(item['id'], 'poison_vial')
        self.assertEqual(item['values'], [3, 6, 9, 12])
        self.assertEqual(item['cooldown_ms'], 3000)
        self.assertEqual(content['shops'][0]['shop'], 'gear_shop')
        self.assertEqual(item['image_size'], [1024, 1024])
        self.assertEqual(item['display_tags'], ['材料'])
        self.assertIn('display_tags = PackedStringArray("材料")', tool.resource(item))

    def test_parameter_edit_changes_resource_and_version(self):
        first, _ = tool.compile_content(self.sheets)
        self.sheets['效果数值']['D10'] = '4'
        changed, _ = tool.compile_content(self.sheets)
        self.assertNotEqual(first['content_version'], changed['content_version'])
        self.assertIn('PackedFloat64Array(4.0, 6.0, 9.0, 12.0)', tool.resource(changed['items'][0]))

    def test_card_values_are_five_digit_unsigned_integers(self):
        for amount in ['100000', '-1', '1.5']:
            with self.subTest(amount=amount):
                source = copy.deepcopy(self.sheets)
                source['效果数值']['D10'] = amount
                with self.assertRaises(tool.InvalidContent):
                    tool.compile_content(source)
        source = copy.deepcopy(self.sheets)
        source['效果数值']['D10'] = '99999'
        self.assertEqual(tool.compile_content(source)[0]['items'][0]['values'][0], 99999)

    def test_multicast_defaults_quality_order_and_bounds(self):
        cells = [f'F{row}' for row, data in tool.rows(self.sheets['品质属性']) if data.get('A') == 'poison_vial']
        for cell in cells:
            self.sheets['品质属性'][cell] = ''
        item = tool.compile_content(self.sheets)[0]['items'][0]
        self.assertEqual(item['multicast'], [1, 1, 1, 1])
        for cell, value in zip(cells, ['2','3','5','10']):
            self.sheets['品质属性'][cell] = value
        item = tool.compile_content(self.sheets)[0]['items'][0]
        self.assertEqual(item['multicast'], [2, 3, 5, 10])
        self.assertIn('tier_multicast = PackedInt32Array(2, 3, 5, 10)', tool.resource(item))
        for value in ['0','11','1.5','oops','-1']:
            with self.subTest(value=value), self.assertRaises(tool.InvalidContent):
                self.sheets['品质属性'][cells[0]] = value
                tool.compile_content(self.sheets)

    def combined_input(self, attributes=('attack','shield')):
        source = copy.deepcopy(self.sheets)
        row = max(n for n,_ in tool.rows(source['效果数值'])) + 1
        for index, attribute in enumerate(attributes):
            fields = ['poison_vial','',attribute,str(index+2),str(index+3),str(index+4),str(index+5)]
            for col,value in zip('ABCDEFG',fields): source['效果数值'][f'{col}{row+index}'] = value
        return source

    def test_multiple_basic_effects_expand_with_independent_values(self):
        expanded, edits = tool.expand_templates(self.combined_input())
        item = tool.compile_content(expanded)[0]['items'][0]
        self.assertEqual([effect['type'] for effect in item['effects']], ['poison','attack','shield'])
        self.assertEqual(item['effects'][1]['values'], [2,3,4,5])
        self.assertEqual(item['effects'][2]['values'], [3,4,5,6])
        self.assertEqual(item['values'], [3,6,9,12])
        self.assertIn('效果配置', edits)
        self.assertFalse(tool.expand_templates(expanded)[1])
        self.assertEqual(tool.expand_templates(expanded)[0], expanded)
        resource = tool.resource(item)
        self.assertIn('load_steps=6', resource)
        self.assertEqual(resource.count('[sub_resource'), 3)

    def test_multiple_effects_limits_duplicates_and_unknown_actions(self):
        for attributes in [('attack','shield','heal'), ('poison',), ('unknown',)]:
            with self.subTest(attributes=attributes), self.assertRaises(tool.InvalidContent):
                expanded,_ = tool.expand_templates(self.combined_input(attributes))
                tool.compile_content(expanded)
        source = self.combined_input(('attack','shield','heal','burn'))
        source['物品总表']['E10'] = '2'
        expanded,_ = tool.expand_templates(source)
        self.assertEqual(len(tool.compile_content(expanded)[0]['items'][0]['effects']),5)

    def test_combined_auto_fill_persists_and_publish_failure_rolls_back(self):
        added = self.combined_input(('shield',))
        cells = {cell:value for cell,value in added['效果数值'].items()
                 if self.sheets['效果数值'].get(cell) != value}
        initial = tool.patch_workbook_bytes(tool.SOURCE.read_bytes(), {'效果数值':cells})
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'items.xlsx'
            output = Path(folder) / 'generated'
            path.write_bytes(initial)
            with patch.object(sys,'argv',['import_items.py','--workbook',str(path)]), \
                 patch.object(tool,'publish',side_effect=OSError('simulated combined failure')):
                self.assertEqual(tool.main(),1)
            self.assertEqual(path.read_bytes(),initial)
            with patch.object(sys,'argv',['import_items.py','--workbook',str(path)]), patch.object(tool,'OUTPUT',output):
                self.assertEqual(tool.main(),0)
                snapshot = path.read_bytes()
                compiled = next(i for i in tool.compile_content(tool.read_workbook(path))[0]['items'] if i['id']=='poison_vial')
                self.assertEqual([effect['type'] for effect in compiled['effects']],['poison','shield'])
                self.assertEqual(tool.main(),0)
                self.assertEqual(path.read_bytes(),snapshot)

    def template_input(self, template='tpl_poison'):
        sheets = copy.deepcopy(self.sheets)
        sheets['物品总表']['G10'] = template
        sheets['物品总表']['C10'] = tool.TEMPLATES[template]
        for key in list(sheets['效果配置']):
            if key.rstrip('0123456789') + '11' == key:
                del sheets['效果配置'][key]
        sheets['效果数值']['B10'] = ''
        sheets['效果数值']['C10'] = ''
        return sheets

    def test_five_templates_create_explicit_snapshots(self):
        for template in tool.TEMPLATES:
            if tool.TEMPLATES[template] in tool.item_special.SPECIAL or template == 'tpl_growth_attack': continue
            with self.subTest(template=template):
                source = self.template_input(template)
                expanded, edits = tool.expand_templates(source)
                item = tool.compile_content(expanded)[0]['items'][0]
                self.assertEqual(item['values'], [3, 6, 9, 12])
                self.assertEqual(item['category'], tool.TEMPLATES[template])
                self.assertIn('效果配置', edits)
                self.assertEqual(source['效果数值']['B10'], '')
                self.assertFalse(tool.expand_templates(expanded)[1])

    def test_template_rejects_unknown_version_category_and_conflicting_parameter(self):
        for sheet, cell, value in [('物品总表', 'H10', '2'), ('物品总表', 'C10', 'weapon'),
                                   ('效果数值', 'C10', 'burn')]:
            source = self.template_input()
            source[sheet][cell] = value
            with self.subTest(cell=cell), self.assertRaises(tool.InvalidContent):
                tool.expand_templates(source)

    def test_snapshot_is_not_overwritten(self):
        source = self.template_input()
        expanded, _ = tool.expand_templates(source)
        expanded['效果配置']['N11'] = '我的独立备注'
        again, edits = tool.expand_templates(expanded)
        self.assertFalse(edits)
        self.assertEqual(again, expanded)

    def test_workbook_patch_preserves_other_parts_and_styles(self):
        source = self.template_input()
        _, edits = tool.expand_templates(source)
        original = tool.SOURCE.read_bytes()
        # Apply the author edits as well as the generated effect snapshot to a temporary copy.
        edits.setdefault('物品总表', {})['G10'] = 'tpl_poison'
        patched = tool.patch_workbook_bytes(original, edits)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'items.xlsx'
            path.write_bytes(patched)
            sheets = tool.read_workbook(path)
            self.assertEqual(sheets['物品总表']['G10'], 'tpl_poison')
            self.assertEqual(sheets['效果配置']['M11'], 'poison')
        with zipfile.ZipFile(tool.io.BytesIO(original)) as before, zipfile.ZipFile(tool.io.BytesIO(patched)) as after:
            changed = [p for p in before.namelist() if before.read(p) != after.read(p)]
            self.assertTrue(set(changed) <= {'xl/worksheets/sheet2.xml', 'xl/worksheets/sheet4.xml', 'xl/worksheets/sheet5.xml'})

    def test_publish_failure_restores_workbook_snapshot(self):
        source = self.template_input()
        edits = {'物品总表': {'G10': 'tpl_poison'}, '效果数值': {'B10': '', 'C10': ''},
                 '效果配置': {c+'11': '' for c in 'ABCDEFGHIJKLMN'}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'items.xlsx'
            path.write_bytes(tool.patch_workbook_bytes(tool.SOURCE.read_bytes(), edits))
            original = path.read_bytes()
            with patch.object(sys, 'argv', ['import_items.py', '--workbook', str(path)]), \
                 patch.object(tool, 'publish', side_effect=OSError('simulated publish failure')):
                self.assertEqual(tool.main(), 1)
            self.assertEqual(path.read_bytes(), original)

    def test_successful_fill_is_saved_and_second_import_is_unchanged(self):
        edits = {'物品总表': {'G10': 'tpl_poison'}, '效果数值': {'B10': '', 'C10': ''},
                 '效果配置': {c+'11': '' for c in 'ABCDEFGHIJKLMN'}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'items.xlsx'
            output = Path(folder) / 'generated'
            path.write_bytes(tool.patch_workbook_bytes(tool.SOURCE.read_bytes(), edits))
            with patch.object(sys, 'argv', ['import_items.py', '--workbook', str(path)]), patch.object(tool, 'OUTPUT', output):
                self.assertEqual(tool.main(), 0)
                snapshot = path.read_bytes()
                resources = {p.name:p.read_bytes() for p in output.iterdir()}
                self.assertFalse(tool.expand_templates(tool.read_workbook(path))[1])
                self.assertEqual(tool.main(), 0)
                self.assertEqual(path.read_bytes(), snapshot)
                self.assertEqual(resources, {p.name:p.read_bytes() for p in output.iterdir()})
                self.assertEqual(len(list((Path(folder) / 'backups').glob('*.xlsx'))), 1)

    def test_zero_is_distinct_from_blank(self):
        self.sheets['效果数值']['D10'] = '0'
        self.assertEqual(tool.compile_content(self.sheets)[0]['items'][0]['values'][0], 0)
        self.sheets['效果数值']['D10'] = ''
        with self.assertRaisesRegex(tool.InvalidContent, '效果数值!D10'):
            tool.compile_content(self.sheets)

    def test_invalid_references_and_unknown_mechanism(self):
        for sheet, cell, value, location in [
            ('效果数值','B10','missing','效果数值!B10'),
            ('效果配置','F11','extra_use','效果配置!F11'),
            ('品质属性','C25','3050','品质属性!C25'),
            ('物品总表','I10','../outside.png','物品总表!I10'),
            ('获取渠道','C10','missing_shop','获取渠道!C10'),
            ('获取渠道','E10','黄金','获取渠道!E10')]:
            with self.subTest(cell=cell, value=value):
                sheets = copy.deepcopy(self.sheets)
                sheets[sheet][cell] = value
                with self.assertRaisesRegex(tool.InvalidContent, location):
                    tool.compile_content(sheets)

    def test_deterministic_publish_and_removal(self):
        content, _ = tool.compile_content(self.sheets)
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'generated'
            tool.publish(content, output)
            first = {p.name:p.read_bytes() for p in output.iterdir()}
            tool.publish(content, output)
            self.assertEqual(first, {p.name:p.read_bytes() for p in output.iterdir()})
            self.sheets['物品总表']['J10'] = '否'
            self.sheets['获取渠道']['G10'] = '否'
            empty, _ = tool.compile_content(self.sheets)
            tool.publish(empty, output)
            self.assertFalse((output/'poison_vial.tres').exists())

    def test_failed_publication_restores_previous_bundle(self):
        content, _ = tool.compile_content(self.sheets)
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'generated'
            tool.publish(content, output)
            before = {p.name:p.read_bytes() for p in output.iterdir()}
            rename = Path.rename
            def fail_stage(path, target):
                if path.name.startswith('.items-stage-'):
                    raise OSError('simulated occupied destination')
                return rename(path,target)
            with patch.object(Path,'rename',fail_stage):
                with self.assertRaises(OSError):
                    tool.publish(content, output)
            self.assertEqual(before,{p.name:p.read_bytes() for p in output.iterdir()})


if __name__ == '__main__':
    unittest.main()
