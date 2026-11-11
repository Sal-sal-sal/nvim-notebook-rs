"""Prepare a Pyright-only cache; never change the runtime Python environment."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).parent))
from archive import interfaces
from download import wheel


def imports(source):
    names = set()
    for line in source.splitlines():
        imported = re.match(r'\s*from\s+([A-Za-z_]\w*)(?:\.\w+)*\s+import\b', line)
        if imported:
            names.add(imported.group(1))
            continue
        try:
            nodes = ast.parse(line.strip()).body
        except SyntaxError:
            continue
        for node in nodes:
            if isinstance(node, ast.Import):
                names.update(name.name.split('.')[0] for name in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
                names.add(node.module.split('.')[0])
    return sorted(name for name in names if name not in sys.stdlib_module_names)


def remove(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def prepare(request, name):
    root, profile = Path(request['root']), Path(request['profile'])
    links = [profile / name, profile / (name + '.pyi')]
    if (root / (name + '.py')).exists() or (root / name).exists() or importlib.util.find_spec(name):
        for path in links:
            remove(path)
        return {'module': name, 'status': 'available'}
    specification = request.get('packages', {}).get(name, name)
    cache = Path(request['cache']) / 'packages' / hashlib.sha256((name + specification).encode()).hexdigest()[:24]
    manifest = cache / 'manifest.json'
    downloaded = False
    valid = manifest.is_file() and json.loads(manifest.read_text(encoding='utf-8')).get('schema') == 1
    if request.get('refresh') or not valid:
        limit = request['max_download_mb'] * 1024 * 1024
        archive, info = wheel(specification, limit)
        with tempfile.TemporaryDirectory(dir=request['cache']) as stage:
            directory = Path(stage)
            info.update(interfaces(archive, directory, name, limit))
            info['schema'] = 1
            (directory / 'manifest.json').write_text(json.dumps(info), encoding='utf-8')
            cache.parent.mkdir(exist_ok=True)
            remove(cache)
            shutil.move(str(directory), str(cache))
        downloaded = True
    info = json.loads(manifest.read_text(encoding='utf-8'))
    for path in links:
        target = cache / path.name
        if target.exists():
            if not path.is_symlink() or path.resolve() != target.resolve():
                remove(path)
                path.symlink_to(target, target_is_directory=target.is_dir())
    return dict(info, module=name, status='cached', downloaded=downloaded)


def main():
    request = json.load(sys.stdin)
    Path(request['profile']).mkdir(parents=True, exist_ok=True)
    results = []
    for name in imports(request['source']):
        if not re.fullmatch(r'[A-Za-z_]\w*', name):
            continue
        try:
            results.append(prepare(request, name))
        except Exception as error:
            results.append({'module': name, 'status': 'unavailable', 'message': str(error)})
    print(json.dumps({'modules': results, 'profile': request['profile']}))


if __name__ == '__main__':
    main()
