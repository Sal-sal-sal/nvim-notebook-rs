"""Small offline package index shared by Python and real Neovim tests."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import threading
import zipfile


def fixture():
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as wheel:
        wheel.writestr('tiny_docs/__init__.py', 'from typing import TYPE_CHECKING\nif TYPE_CHECKING:\n'
                       '    from .pipelines import pipeline as pipeline\nelse:\n    raise RuntimeError("never execute")\n')
        wheel.writestr('tiny_docs/pipelines.py', '''from __future__ import annotations
class Pipeline:
    def generate(self, text: str, max_length: int = 20) -> str:
        """Generate documented text without loading a model."""
        raise RuntimeError("never execute")
def pipeline(task: str, model: str | None = None) -> Pipeline:
    """Build a documented pipeline for the specified task and model."""
    raise RuntimeError("never execute")
''')
        wheel.writestr('tiny_docs/model.safetensors', b'model weights must not be extracted')
        wheel.writestr('tiny_docs/native.so', b'native code must not be extracted')
        wheel.writestr('tiny_docs-1.0.dist-info/licenses/LICENSE', 'Test fixture license')
    return archive.getvalue()


class Index:
    def __init__(self, directory=None):
        self.archive, self.requests, self.size, self.checksum = fixture(), [], None, None
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                owner.requests.append(self.path)
                if directory:
                    (Path(directory) / 'requests.json').write_text(json.dumps(owner.requests))
                if self.path in {'/pypi/tiny_docs/json', '/pypi/tiny-docs/json'}:
                    data = {'info': {'version': '1.0'}, 'urls': [{'filename': 'tiny_docs-1.0-py3-none-any.whl',
                        'size': owner.size or len(owner.archive), 'url': owner.url + '/fixture.whl',
                        'digests': {'sha256': owner.checksum or hashlib.sha256(owner.archive).hexdigest()}}]}
                    body = json.dumps(data).encode()
                elif self.path == '/fixture.whl':
                    body = owner.archive
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


if __name__ == '__main__':
    import sys
    index = Index(sys.argv[1])
    (Path(sys.argv[1]) / 'port').write_text(index.url + '/pypi')
    index.thread.join()
