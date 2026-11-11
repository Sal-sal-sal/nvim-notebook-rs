"""Extract interfaces and docstrings only; discard code, binaries, and weights."""
import io
from pathlib import PurePosixPath
import zipfile

from signatures import convert


def interfaces(data, destination, module, limit):
    count, size, skipped = 0, 0, 0
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if sum(item.file_size for item in archive.infolist()) > limit * 10:
            raise ValueError('documentation archive exceeds the unpacked size limit')
        selected = {}
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            if path.is_absolute() or '..' in path.parts or not path.parts or any('\\' in part or ':' in part for part in path.parts):
                raise ValueError('unsafe path in documentation wheel')
            # PEP 561 stub distributions use a package directory named foo-stubs.
            parts = (module,) + path.parts[1:] if path.parts[0] == module + '-stubs' else path.parts
            path = PurePosixPath(*parts)
            if path.parts[0] != module and path.name not in {module + '.py', module + '.pyi'}:
                continue
            if path.suffix not in {'.py', '.pyi'}:
                continue
            target = path.with_suffix('.pyi')
            if target not in selected or path.suffix == '.pyi':
                selected[target] = item
        for relative, item in selected.items():
            try:
                source = archive.read(item).decode('utf-8-sig')
                interface = source if item.filename.endswith('.pyi') else convert(source)
            except (SyntaxError, UnicodeError, ValueError, RecursionError):
                skipped += 1
                continue
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(interface, encoding='utf-8')
            count, size = count + 1, size + len(interface.encode('utf-8'))
        for item in archive.infolist():
            if '.dist-info/' in item.filename and PurePosixPath(item.filename).name.upper().startswith(('LICENSE', 'NOTICE')):
                if item.file_size <= 128 * 1024:
                    target = destination / 'licenses' / PurePosixPath(item.filename).name
                    target.parent.mkdir(exist_ok=True)
                    target.write_bytes(archive.read(item))
    if not count:
        raise ValueError('wheel contains no Python interfaces for import ' + module)
    return {'files': count, 'interface_bytes': size, 'skipped_modules': skipped}
