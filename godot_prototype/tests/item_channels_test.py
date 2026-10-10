import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import import_items as tool


class ChannelsTest(unittest.TestCase):
    def setUp(self):
        self.sheets=tool.read_workbook(tool.SOURCE)

    def add(self,kind,pool,low='白银',high='黄金',weight='100000'):
        n=max(n for n,_ in tool.rows(self.sheets['获取渠道']))+1
        for col,v in zip('ABCDEFG',['shield_dagger',kind,pool,weight,low,high,'是']):
            self.sheets['获取渠道'][f'{col}{n}']=v
        return n

    def test_supported_channels_and_fixture(self):
        self.add('drop','bandit')
        self.add('event','material_small')
        self.add('quest','side_road_bandit')
        payload,_=tool.compile_content(self.sheets)
        self.assertEqual({r['type']for r in payload['channels']},{'drop','event','quest'})
        self.assertTrue(all(r['min_quality']==1 and r['max_quality']==2 for r in payload['channels']))
        fixture=Path(__file__).parent/'fixtures/reward_channels.json'
        fixture.write_text(json.dumps(payload['channels'],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

    def test_invalid_pool_bounds_weight_and_duplicates(self):
        for kind,pool,low,high,weight,cell in [
            ('drop','missing','青铜','钻石','1','C'),
            ('event','missing','青铜','钻石','1','C'),
            ('quest','missing','青铜','钻石','1','C'),
            ('drop','bandit','黄金','白银','1','E'),
            ('drop','bandit','青铜','钻石','0','D')]:
            with self.subTest(kind=kind,cell=cell):
                self.sheets=tool.read_workbook(tool.SOURCE)
                n=self.add(kind,pool,low,high,weight)
                with self.assertRaisesRegex(tool.InvalidContent,f'获取渠道!{cell}{n}'):
                    tool.compile_content(self.sheets)
        self.sheets=tool.read_workbook(tool.SOURCE)
        self.add('drop','bandit');n=self.add('drop','bandit')
        with self.assertRaisesRegex(tool.InvalidContent,f'获取渠道!C{n}'):
            tool.compile_content(self.sheets)

    def test_migrated_special_contracts_and_passive(self):
        payload,_=tool.compile_content(self.sheets)
        items={i['id']:i for i in payload['items']}
        self.assertEqual(len(items),16)
        self.assertEqual(items['ward_charm']['self_passive'],'charge_on_weapon_use')
        self.assertEqual(items['recovery_draught']['fixed_base_price'],6)
        self.assertEqual(items['recovery_draught']['out_of_combat_heal'],30)
        self.assertFalse(items['scrap_material']['equippable'])
        self.assertEqual(items['stimulator']['effects'][0]['target'],'own_other_active_item')
        self.assertEqual(items['frost_seal']['values'],[1000,1500,2000,2500])

    def test_control_template_autofill_and_duration_validation(self):
        sheets=copy.deepcopy(self.sheets)
        en=next(n for n,r in tool.rows(sheets['效果配置'])if r.get('A')=='stimulator')
        for col in 'ABCDEFGHIJKLMN':sheets['效果配置'][f'{col}{en}']=''
        expanded,edits=tool.expand_templates(sheets)
        self.assertIn('效果配置',edits)
        item=next(i for i in tool.compile_content(expanded)[0]['items']if i['id']=='stimulator')
        self.assertEqual(item['effects'][0]['type'],'haste')
        vn=next(n for n,r in tool.rows(expanded['效果数值'])if r.get('A')=='stimulator')
        expanded['效果数值'][f'D{vn}']='123'
        with self.assertRaisesRegex(tool.InvalidContent,'100 毫秒'):
            tool.compile_content(expanded)

    def test_passive_and_noncombat_fields_reject_silent_changes(self):
        for field,value in [('B5','unknown_passive'),('B4','错误表头')]:
            with self.subTest(field=field):
                source=copy.deepcopy(self.sheets)
                source['物品扩展'][field]=value
                with self.assertRaises(tool.InvalidContent):tool.compile_content(source)
        source=copy.deepcopy(self.sheets)
        rn=next(n for n,r in tool.rows(source['品质属性'])if r.get('A')=='recovery_draught')
        for n,row in tool.rows(source['品质属性']):
            if row.get('A')=='recovery_draught':source['品质属性'][f'D{n}']='7'
        with self.assertRaisesRegex(tool.InvalidContent,'偶数'):tool.compile_content(source)


if __name__=='__main__': unittest.main()
