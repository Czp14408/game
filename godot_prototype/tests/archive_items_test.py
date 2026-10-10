import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import archive_items as tool
import import_items as importer


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.workbook = self.folder/'items.xlsx'
        shutil.copyfile(importer.SOURCE,self.workbook)
        self.generated = self.folder/'generated'
        payload,_ = importer.compile_content(importer.read_workbook(self.workbook))
        importer.publish(payload,self.generated)
        self.output = self.folder/'archives'

    def tearDown(self):
        self.temp.cleanup()

    def test_archive_checksums_idempotency_and_source_protection(self):
        before = self.workbook.read_bytes()
        resources = {p.name:p.read_bytes() for p in self.generated.iterdir()}
        target = tool.archive(self.workbook,self.generated,self.output)
        self.assertEqual(tool.archive(self.workbook,self.generated,self.output),target)
        self.assertEqual(len(list(self.output.glob('*.zip'))),1)
        with zipfile.ZipFile(target) as bundle:
            self.assertIsNone(bundle.testzip())
            summary=json.loads(bundle.read('archive-summary.json'))
            for name, digest in summary['sha256'].items():
                self.assertEqual(hashlib.sha256(bundle.read(name)).hexdigest(),digest)
            self.assertEqual(bundle.read('content/items.xlsx'),before)
            self.assertIn('godot_prototype/assets/items/icons/shield_dagger.png',bundle.namelist())
        self.assertEqual(self.workbook.read_bytes(),before)
        self.assertEqual({p.name:p.read_bytes() for p in self.generated.iterdir()},resources)
        self.assertFalse(self.generated.with_name('.items-import.lock').exists())

    def test_changed_excel_requires_update(self):
        self.workbook.write_bytes(importer.patch_workbook_bytes(self.workbook.read_bytes(),{'物品总表':{'B11':'盾匕修改'}}))
        with self.assertRaisesRegex(ValueError,'不一致'):
            tool.archive(self.workbook,self.generated,self.output)
        self.assertFalse(self.output.exists())

    def test_tampered_resource_requires_update(self):
        path=self.generated/'shield_dagger.tres'
        path.write_text('invalid',encoding='utf-8')
        with self.assertRaisesRegex(ValueError,'勿手改'):
            tool.archive(self.workbook,self.generated,self.output)

    def test_lock_does_not_get_removed_if_owned_elsewhere(self):
        lock=self.generated.with_name('.items-import.lock')
        lock.write_text('occupied')
        with self.assertRaisesRegex(ValueError,'正在进行'):
            tool.archive(self.workbook,self.generated,self.output)
        self.assertTrue(lock.exists())


if __name__=='__main__':
    unittest.main()
