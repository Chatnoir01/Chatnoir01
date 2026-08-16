#!/usr/bin/env python3
"""Download and inspect one official UrbIS Landscape ZIP tile without committing it."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS Landscape tile inspection)"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--discovery", type=Path, required=True)
    parser.add_argument("--tile", required=True)
    parser.add_argument("--download-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def select_url(discovery: dict, tile: str) -> str:
    matches = []
    for item in discovery.get("candidate_links", []):
        if tile in item.get("matching_tiles", []):
            url = str(item.get("url", ""))
            if url.lower().endswith(".zip"):
                matches.append(url)
    if not matches:
        raise SystemExit(f"No official ZIP candidate found for tile {tile}")
    # The Atom feed is authoritative. If several versions appear, prefer the
    # lexicographically newest dated filename rather than inventing a version.
    return sorted(matches)[-1]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    args = parse_args()
    discovery = json.loads(args.discovery.read_text(encoding="utf-8"))
    url = select_url(discovery, args.tile)
    args.download_dir.mkdir(parents=True, exist_ok=True)
    zip_path = args.download_dir / Path(url).name

    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, zip_path.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)

    members: list[dict] = []
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            members.append({
                "name": info.filename,
                "compressed_size": info.compress_size,
                "uncompressed_size": info.file_size,
                "extension": Path(info.filename).suffix.lower(),
                "is_dir": info.is_dir(),
            })

    inventory = {
        "schema": 1,
        "source": "Paradigm UrbIS Landscape Atom feed",
        "dataset_id": discovery.get("dataset_id"),
        "tile": args.tile,
        "url": url,
        "source_crs": "EPSG:31370",
        "downloaded_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "size_bytes": zip_path.stat().st_size,
        "sha256": sha256_file(zip_path),
        "members": members,
        "policy": "The ZIP/SKP source is inspected in CI only and is not committed. This JSON preserves provenance and archive structure for the future terrain/3D conversion pipeline.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("URBIS_LANDSCAPE_TILE_OK", args.tile, zip_path.stat().st_size, inventory["sha256"])
    for member in members:
        print("MEMBER", member["extension"], member["uncompressed_size"], member["name"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
