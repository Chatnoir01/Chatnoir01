#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, time, urllib.request, zipfile
from pathlib import Path, PurePosixPath

URLS = [
    'https://extensions.blender.org/download/sha256:4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87/add-on-mpfb-v2.0.17.zip',
]
EXPECTED_SIZE = 45_031_536
EXPECTED_SHA256 = '4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87'
EXPECTED_VERSION = '2.0.17'
EXPECTED_BUILD = '20260722'
EXPECTED_BLENDER_MIN = '4.2.0'


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def _extension_identity(z: zipfile.ZipFile) -> tuple[str, str]:
    names = [name for name in z.namelist() if not name.endswith('/')]
    manifests = [name for name in names if PurePosixPath(name).name == 'blender_manifest.toml']
    if not manifests:
        raise ValueError('MPFB blender_manifest.toml missing')
    manifest_name = min(manifests, key=lambda name: (name.count('/'), len(name)))
    parent = str(PurePosixPath(manifest_name).parent)
    init_name = '__init__.py' if parent == '.' else f'{parent}/__init__.py'
    if init_name not in names:
        raise ValueError(f'MPFB __init__.py missing next to manifest: {manifest_name}')
    return manifest_name, init_name


def validate(path: Path) -> dict:
    size = path.stat().st_size
    digest = sha256(path)
    if size != EXPECTED_SIZE:
        raise ValueError(f'MPFB size mismatch: expected {EXPECTED_SIZE}, got {size}')
    if digest != EXPECTED_SHA256:
        raise ValueError(f'MPFB sha256 mismatch: expected {EXPECTED_SHA256}, got {digest}')
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            raise ValueError(f'MPFB CRC failure: {bad}')
        manifest_name, init_name = _extension_identity(z)
        manifest = z.read(manifest_name).decode('utf-8')
        init_py = z.read(init_name).decode('utf-8')
    if f'version = "{EXPECTED_VERSION}"' not in manifest:
        raise ValueError('MPFB manifest version mismatch')
    if f'blender_version_min = "{EXPECTED_BLENDER_MIN}"' not in manifest:
        raise ValueError('MPFB minimum Blender version mismatch')
    if f'BUILD_INFO = "{EXPECTED_BUILD}"' not in init_py:
        raise ValueError('MPFB build mismatch')
    return {
        'size_bytes': size,
        'sha256': digest,
        'version': EXPECTED_VERSION,
        'build': EXPECTED_BUILD,
        'blender_version_min': EXPECTED_BLENDER_MIN,
        'manifest_path': manifest_name,
    }


def download(url: str, target: Path, retries: int) -> None:
    for attempt in range(1, retries + 1):
        tmp = target.with_suffix(target.suffix + '.part')
        tmp.unlink(missing_ok=True)
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Grand-Bruxelles-MPFB-Pinned-Fetcher/1'})
            with urllib.request.urlopen(req, timeout=180) as response, tmp.open('wb') as out:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
            os.replace(tmp, target)
            return
        except Exception:
            tmp.unlink(missing_ok=True)
            if attempt == retries:
                raise
            time.sleep(attempt * 2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--retries', type=int, default=3)
    args = ap.parse_args()
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    last = None
    for url in URLS:
        try:
            print('FETCH', url)
            download(url, target, args.retries)
            meta = validate(target)
            meta.update({
                'source': url,
                'mirrors': URLS,
                'license': 'GPL-3.0-or-later add-on; generated outputs not claimed by MPFB',
                'distribution': 'Blender Extensions approved MPFB 2.0.17 archive',
            })
            Path(args.manifest).write_text(json.dumps(meta, indent=2, sort_keys=True), encoding='utf-8')
            print(
                f"MPFB_2017_FETCH_OK bytes={meta['size_bytes']} sha256={meta['sha256']} "
                f"version={meta['version']} build={meta['build']} source={url}"
            )
            return 0
        except Exception as exc:
            print('FETCH_FAIL', url, repr(exc))
            last = exc
            target.unlink(missing_ok=True)
    print(f'MPFB_2017_FETCH_FAIL: {last}')
    return 1

if __name__ == '__main__':
    raise SystemExit(main())
