#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

MIRRORS = (
    "https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip",
    "https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip",
)
MIN_ARCHIVE_BYTES = 200 * 1024 * 1024
USER_AGENT = "Grand-Bruxelles-MakeHuman-System-Assets-Fetcher/1"
CHUNK_SIZE = 4 * 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_zip(path: Path) -> dict:
    if not path.is_file():
        raise ValueError(f"archive missing: {path}")
    size = path.stat().st_size
    if size < MIN_ARCHIVE_BYTES:
        raise ValueError(
            f"archive too small: {size} bytes (minimum {MIN_ARCHIVE_BYTES})"
        )
    if not zipfile.is_zipfile(path):
        raise ValueError("download is not a valid ZIP archive")

    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad is not None:
            raise ValueError(f"ZIP CRC check failed at {bad}")
        infos = [entry for entry in archive.infolist() if not entry.is_dir()]
        names = [entry.filename.lower() for entry in infos]
        file_count = len(names)
        uncompressed_bytes = sum(entry.file_size for entry in infos)

    if file_count < 100:
        raise ValueError(f"unexpectedly small asset pack: only {file_count} files")

    signals = {
        "skin": any("skin" in name for name in names),
        "eyes": any("eye" in name for name in names),
        "teeth": any("teeth" in name or "tooth" in name for name in names),
        "makehuman_asset": any(
            name.endswith(ext)
            for name in names
            for ext in (".mhmat", ".mhclo", ".proxy", ".target", ".obj")
        ),
    }
    missing = [key for key, present in signals.items() if not present]
    if missing:
        raise ValueError(
            "ZIP is readable but does not look like MakeHuman System Assets; "
            f"missing signals: {', '.join(missing)}"
        )

    return {
        "size_bytes": size,
        "file_count": file_count,
        "uncompressed_bytes": uncompressed_bytes,
        "signals": signals,
        "sha256": sha256_file(path),
    }


def download(url: str, destination: Path, retries: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + ".part")
    if partial.exists():
        partial.unlink()

    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=180) as response, partial.open("wb") as out:
                expected = response.headers.get("Content-Length")
                copied = 0
                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    out.write(chunk)
                    copied += len(chunk)
                if expected is not None and copied != int(expected):
                    raise OSError(
                        f"incomplete HTTP body: expected {expected} bytes, got {copied}"
                    )
            os.replace(partial, destination)
            return
        except (OSError, urllib.error.URLError, urllib.error.HTTPError) as exc:
            if partial.exists():
                partial.unlink()
            if attempt == retries:
                raise
            print(
                f"retry {attempt}/{retries} failed for {url}: {exc}",
                file=sys.stderr,
            )
            time.sleep(min(5 * attempt, 20))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download and validate the official MakeHuman System Assets CC0 pack."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("makehuman_system_assets_cc0.zip"),
        help="destination ZIP path",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="optional JSON witness path",
    )
    parser.add_argument("--retries", type=int, default=3)
    args = parser.parse_args()

    output = args.output.resolve()
    manifest_path = args.manifest.resolve() if args.manifest else None

    if output.exists():
        try:
            details = validate_zip(output)
            source = "existing_verified"
        except ValueError:
            output.unlink()
            details = None
            source = ""
    else:
        details = None
        source = ""

    errors: list[str] = []
    if details is None:
        for url in MIRRORS:
            try:
                print(f"FETCH {url}")
                download(url, output, max(1, args.retries))
                details = validate_zip(output)
                source = url
                break
            except (OSError, ValueError, urllib.error.URLError, urllib.error.HTTPError) as exc:
                errors.append(f"{url}: {exc}")
                if output.exists():
                    output.unlink()

    if details is None:
        print("MAKEHUMAN_SYSTEM_ASSETS_FETCH_FAIL", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    witness = {
        "artifact": output.name,
        "source": source,
        "mirrors": list(MIRRORS),
        "license": "CC0 core assets (official MakeHuman Community source)",
        **details,
    }

    if manifest_path:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(witness, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    print(
        "MAKEHUMAN_SYSTEM_ASSETS_FETCH_OK "
        f"bytes={details['size_bytes']} files={details['file_count']} "
        f"sha256={details['sha256']} source={source}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
