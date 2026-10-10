import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import import_items as tool
from item_import_report import write_report


class ReportTest(unittest.TestCase):
    def test_changes_check_status_and_html_escape(self):
        payload, warnings = tool.compile_content(tool.expand_templates(tool.read_workbook(tool.SOURCE))[0])
        changed_id=payload['items'][0]['id']
        payload['items'][0]['name'] = '<script>unsafe</script>'
        previous = {'items': [dict(payload['items'][0], name='old'), {'id': 'removed'}]}
        with tempfile.TemporaryDirectory() as folder:
            path = write_report(folder, tool.SOURCE, checked=True, payload=payload, previous=previous, warnings=warnings)
            data = json.loads(path.with_suffix('.json').read_text(encoding='utf-8'))
            self.assertEqual(data['status'], '校验通过，未更新工程')
            self.assertEqual(data['changes']['删除'], ['removed'])
            self.assertEqual(data['changes']['修改'], [changed_id])
            self.assertNotIn('<script>unsafe', path.read_text(encoding='utf-8'))

    def test_error_cell_and_no_false_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = write_report(folder, tool.SOURCE, checked=False, error='效果数值!D10：需要整数')
            data = json.loads(path.with_suffix('.json').read_text(encoding='utf-8'))
            self.assertEqual(data['error_cells'], [{'sheet':'效果数值','cell':'D10'}])
            self.assertEqual(data['changes'], {})
            self.assertEqual(data['status'], '更新失败，保留上一版')

    def test_report_failure_does_not_turn_success_into_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'generated'
            with patch.object(sys, 'argv', ['import_items.py']), patch.object(tool, 'OUTPUT', output), patch.object(tool, 'write_report', side_effect=OSError('occupied report')):
                self.assertEqual(tool.main(), 0)
                self.assertTrue((output/'manifest.json').exists())


if __name__ == '__main__':
    unittest.main()
