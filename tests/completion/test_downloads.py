import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from server import Index


class Downloads(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.index = Index()
        self.binary = os.environ.get('NOTEBOOK_RS_BIN', str(Path(__file__).resolve().parents[2] / 'target/release/nvim-notebook-rs'))
        self.request = {'python': sys.executable, 'cache': str(self.directory / 'cache'),
            'profile': str(self.directory / 'profile'), 'root': str(self.directory),
            'source': 'from tiny_docs import pipeline\n', 'packages': {}, 'max_download_mb': 1}

    def tearDown(self):
        self.index.close()
        self.temporary.cleanup()

    def run_docs(self):
        env = dict(os.environ, NVIM_NOTEBOOK_DOCS_INDEX=self.index.url + '/pypi')
        result = subprocess.run([self.binary, 'library-docs'], input=json.dumps(self.request), text=True,
                                capture_output=True, check=True, env=env, timeout=30)
        return json.loads(result.stdout)['modules']

    def test_cache_is_offline_reusable_and_does_not_install_importable_code(self):
        modules = self.run_docs()
        self.assertEqual(modules[0]['status'], 'cached')
        self.assertEqual(modules[0]['version'], '1.0')
        self.assertTrue(modules[0]['downloaded'])
        stub = self.directory / 'profile/tiny_docs/pipelines.pyi'
        self.assertIn('Build a documented pipeline', stub.read_text())
        self.assertFalse(any(self.directory.rglob('*.py')))
        self.assertFalse(any(self.directory.rglob('*.so')))
        self.assertFalse(any(self.directory.rglob('*.safetensors')))
        self.assertIsNone(importlib.util.find_spec('tiny_docs'))
        requests = len(self.index.requests)
        self.assertFalse(self.run_docs()[0]['downloaded'])
        self.assertEqual(len(self.index.requests), requests, 'warm cache made another network request')
        self.request['refresh'] = True
        self.assertTrue(self.run_docs()[0]['downloaded'])

    def test_heavy_wheel_is_rejected_before_it_is_downloaded(self):
        self.index.size = 2 * 1024 * 1024
        modules = self.run_docs()
        self.assertEqual(modules[0]['status'], 'unavailable')
        self.assertIn('download limit', modules[0]['message'])
        self.assertNotIn('/fixture.whl', self.index.requests)

    def test_bad_checksum_does_not_replace_a_working_cache(self):
        self.run_docs()
        original = (self.directory / 'profile/tiny_docs/pipelines.pyi').read_bytes()
        self.request['refresh'] = True
        self.index.checksum = '0' * 64
        self.assertIn('checksum', self.run_docs()[0]['message'])
        self.assertEqual((self.directory / 'profile/tiny_docs/pipelines.pyi').read_bytes(), original)

    def test_local_modules_and_stdlib_are_not_downloaded(self):
        self.request['source'] = 'import math\nfrom tiny_docs import pipeline\n'
        (self.directory / 'tiny_docs.py').write_text('local = True')
        self.assertEqual(self.run_docs()[0]['status'], 'available')
        self.assertEqual(self.index.requests, [])

    def test_multiline_import_and_incomplete_cell_still_prepare_documentation(self):
        self.request['source'] = 'from tiny_docs import (\n    pipeline,\n)\n\npipeline(\n'
        self.assertEqual(self.run_docs()[0]['status'], 'cached')


if __name__ == '__main__':
    unittest.main()
