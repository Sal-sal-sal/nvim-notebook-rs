import ast
import io
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'src/completion'))
from archive import interfaces
from signatures import convert


class Interfaces(unittest.TestCase):
    def test_preserves_signatures_docs_and_exports_without_implementation(self):
        source = '''"""Module documentation."""
from __future__ import annotations
from missing_module import Model
from typing import TYPE_CHECKING, overload
if TYPE_CHECKING:
    from .other import Public
else:
    raise RuntimeError('must not execute')
@expensive_runtime_decorator()
def pipeline(task: str, model: Model | None = None, device=allocate_gpu()) -> Model:
    """Build the requested pipeline."""
    download_weights()
    return run_model()
'''
        result = convert(source)
        compile(result, '<stub>', 'exec')
        self.assertIn('Build the requested pipeline.', result)
        self.assertIn('from .other import Public as Public', result)
        self.assertIn('device=...', result)
        self.assertNotIn('download_weights', result)
        self.assertNotIn('allocate_gpu', result)
        self.assertNotIn('expensive_runtime_decorator', result)
        self.assertFalse(any(isinstance(item, ast.Call) for item in ast.walk(ast.parse(result))))

    def test_keeps_native_stubs_and_discards_binaries_weights_and_install_hooks(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as wheel:
            wheel.writestr('demo-stubs/__init__.pyi', 'def run(value: str) -> str:\n    """Native stub documentation."""\n    ...\n')
            wheel.writestr('demo-stubs/__init__.py', 'raise RuntimeError("wrong source")')
            wheel.writestr('demo-stubs/native.so', b'not allowed')
            wheel.writestr('demo-stubs/weights.safetensors', b'not allowed')
            wheel.writestr('install.pth', 'import malicious_code')
        with tempfile.TemporaryDirectory() as directory:
            info = interfaces(buffer.getvalue(), Path(directory), 'demo', 1024 * 1024)
            self.assertEqual(info['files'], 1)
            self.assertIn('Native stub documentation', (Path(directory) / 'demo/__init__.pyi').read_text())
            self.assertEqual([str(path.relative_to(directory)) for path in Path(directory).rglob('*') if path.is_file()],
                             ['demo/__init__.pyi'])

    def test_rejects_archive_path_traversal_and_unpacked_limits(self):
        for name in ['../escape.py', '/absolute.py', 'demo/..\\escape.py']:
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, 'w') as wheel:
                wheel.writestr(name, 'pass')
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, 'unsafe path'):
                    interfaces(buffer.getvalue(), Path(directory), 'demo', 1024)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as wheel:
            wheel.writestr('demo/__init__.py', ' ' * 10001)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'unpacked size'):
                interfaces(buffer.getvalue(), Path(directory), 'demo', 100)


if __name__ == '__main__':
    unittest.main()
