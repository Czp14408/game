"""Archive an applied item generation without changing workbook or game data."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import zipfile

import import_items as importer


def archive(workbook, generated, directory, project=importer.PROJECT):
    workbook, generated, directory, project = map(Path, (workbook, generated, directory, project))
    lock = generated.with_name('.items-import.lock')
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise ValueError('物品更新或归档正在进行，请稍后重试。')
    os.close(descriptor)
    try:
        original = workbook.read_bytes()
        sheets, edits = importer.expand_templates(importer.read_workbook(workbook))
        if edits:
            raise ValueError('配置仍需自动补齐，请先保存关闭 Excel 并运行 update_items.cmd。')
        payload, warnings = importer.compile_content(sheets, project=project)
        manifest = generated/'manifest.json'
        if not manifest.exists() or json.loads(manifest.read_text(encoding='utf-8')) != payload:
            raise ValueError('Excel 或图片与已生成内容不一致，请先运行 update_items.cmd。')
        snapshots = {workbook: ('content/items.xlsx', original), manifest: ('godot_prototype/data/generated_items/manifest.json', manifest.read_bytes())}
        expected = {item['id']+'.tres' for item in payload['items']}
        if {p.name for p in generated.glob('*.tres')} != expected:
            raise ValueError('生成资源清单不一致，请先运行 update_items.cmd。')
        for item in payload['items']:
            resource = generated/(item['id']+'.tres')
            if resource.read_text(encoding='utf-8') != importer.resource(item):
                raise ValueError(f'{resource.name} 与配置不一致，请先更新工程，勿手改生成资源。')
            snapshots[resource] = ('godot_prototype/data/generated_items/'+resource.name, resource.read_bytes())
            if not item['icon']: continue
            image = (project/item['icon']).resolve()
            image_bytes = image.read_bytes()
            if hashlib.sha256(image_bytes).hexdigest() != item['icon_sha256']:
                raise ValueError('图片在归档期间发生变化，请重新运行。')
            snapshots[image] = ('godot_prototype/'+item['icon'], image_bytes)
        for relative in ['assets/palettes/game-128-v1.json', 'assets/palettes/game-128-v1.gpl']:
            path = project/relative
            snapshots[path] = ('godot_prototype/'+relative, path.read_bytes())
        for shop_id in {rule['shop'] for rule in payload['shops']}:
            path = project/'data/shops'/(shop_id+'.tres')
            snapshots[path] = ('godot_prototype/data/shops/'+path.name, path.read_bytes())
        registry = project.parent/'content/migrated-items.json'
        if registry.exists(): snapshots[registry]=('content/migrated-items.json',registry.read_bytes())
        for rule in payload.get('channels',[]):
            if rule['type']=='drop':
                path=project/'data/enemies'/(rule['pool']+'.tres')
                snapshots[path]=('godot_prototype/data/enemies/'+path.name,path.read_bytes())
            elif rule['type']=='quest':
                for path in (project/'data/worlds').glob('*.tres'):
                    snapshots[path]=('godot_prototype/data/worlds/'+path.name,path.read_bytes())
        exemption = project.parent/'content/legacy-art-palette-exemptions.json'
        if exemption.exists():
            snapshots[exemption] = ('content/'+exemption.name, exemption.read_bytes())
        files = {name: data for name, data in snapshots.values()}
        checksums = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}
        identity = hashlib.sha256(json.dumps(checksums, sort_keys=True).encode()).hexdigest()[:12]
        summary = dict(content_version=payload['content_version'], snapshot=identity,
                       items=[dict(id=i['id'], name=i['name']) for i in payload['items']],
                       warnings=warnings, sha256=checksums)
        files['archive-summary.json'] = (json.dumps(summary,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
        files['使用说明.txt'] = ('物品配置与素材留档包，不是可独立运行的游戏。\n'
            '包含当前工作簿、启用物品专属图片、生成资源、相关商店定义、调色板及文件摘要。\n'
            '不包含游戏脚本、运行存档、禁用物品图片或完整工程。\n'
            '恢复时先解压到独立目录，对比原工程，不要直接整包覆盖。\n'
            '需要恢复配置时先备份当前工程，再恢复 Excel 与所需图片并运行 update_items.cmd，完成报告和预览验收。\n'
            '商店及色表变更需单独核对；生成资源以重新导入为准。\n').encode('utf-8')
        for path, (_, data) in snapshots.items():
            if path.read_bytes() != data:
                raise ValueError(f'归档期间文件发生变化：{path}，请重新运行。')
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
            for name, data in sorted(files.items()):
                entry = zipfile.ZipInfo(name, date_time=(2026,1,1,0,0,0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(entry, data)
        data = buffer.getvalue()
        directory.mkdir(parents=True, exist_ok=True)
        target = directory/(payload['content_version']+'-'+identity+'.zip')
        if target.exists():
            if target.read_bytes() != data:
                raise ValueError('同名留档文件内容不同，请保留旧包并更换归档目录。')
            return target
        with target.open('xb') as stream:
            try:
                stream.write(data)
            except BaseException:
                stream.close()
                target.unlink(missing_ok=True)
                raise
        return target
    finally:
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description='归档已导入的物品配置与素材，不修改工程')
    parser.add_argument('--workbook',type=Path,default=importer.SOURCE)
    parser.add_argument('--archive-dir',type=Path,default=importer.SOURCE.parent/'archives')
    args = parser.parse_args()
    try:
        target = archive(args.workbook, importer.OUTPUT, args.archive_dir)
        print(f'物品留档完成：{target.resolve()}')
        print('相同快照重复使用同一包；工作簿与工程未修改。此包不包含完整游戏。')
        return 0
    except (OSError,ValueError,KeyError,zipfile.BadZipFile,importer.InvalidContent) as error:
        print(f'归档失败：{error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
