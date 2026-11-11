"""Fetch wheels from package metadata, with no installer or dependency resolver."""
import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request


def fetch(url, limit):
    request = urllib.request.Request(url, headers={'User-Agent': 'nvim-notebook-rs/library-docs'})
    with urllib.request.urlopen(request, timeout=20) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('documentation download exceeds the configured size limit')
    return data


def metadata(package, version=None):
    base = os.environ.get('NVIM_NOTEBOOK_DOCS_INDEX', 'https://pypi.org/pypi').rstrip('/')
    url = base + '/' + urllib.parse.quote(package, safe='')
    if version:
        url += '/' + urllib.parse.quote(version, safe='')
    return json.loads(fetch(url + '/json', 5 * 1024 * 1024))


def wheel(specification, limit):
    match = re.fullmatch(r'([A-Za-z0-9][A-Za-z0-9_.-]*)(?:==([A-Za-z0-9][A-Za-z0-9_.+!-]*))?', specification)
    if not match:
        raise ValueError('use a package name or package==version for documentation')
    package, version = match.groups()
    candidates = [(package, version)]
    if version is None:
        candidates.extend([('types-' + package, None), (package + '-stubs', None)])
    for name, selected in candidates:
        try:
            data = metadata(name, selected)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                continue
            raise
        files = [item for item in data.get('urls', []) if item['filename'].endswith('.whl')
                 and not item.get('yanked') and item['size'] <= limit]
        files.sort(key=lambda item: (not item['filename'].endswith('-none-any.whl'), item['size']))
        if not files:
            continue
        item = files[0]
        archive = fetch(item['url'], limit)
        if hashlib.sha256(archive).hexdigest() != item['digests']['sha256']:
            raise ValueError('documentation wheel checksum does not match package metadata')
        return archive, {'package': name, 'version': data['info']['version'], 'url': item['url'],
                         'sha256': item['digests']['sha256'], 'download_bytes': len(archive)}
    raise ValueError('no wheel or type-stub package within the documentation download limit')
