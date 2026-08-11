#!/usr/bin/env python3
"""Download and inspect one official UrbIS DTM ZIP tile without committing source rasters."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS DTM tile inspection)"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--discovery", type=Path, required=True)
    parser.add_argument("--tile", required=True)
    parser.add_argument("--download-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def select_url(discovery: dict, tile: str) -> str:
    matches: list[str] = []
    for item in discovery.get("candidate_links", []):
        if tile in item.get("matching_tiles", []):
            url = str(item.get("url", ""))
            if url.lower().endswith(".zip"):
                matches.append(url)
    if not matches:
        raise SystemExit(f"No official DTM ZIP candidate found for tile {tile}")
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
    with urllib.request.urlopen(request, timeout=180) as response, zip_path.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)

    if not zipfile.is_zipfile(zip_path):
        raise SystemExit(f"Downloaded file is not a valid ZIP: {zip_path}")

    members: list[dict] = []
    raster_members: list[str] = []
    with zipfile.ZipFile(zip_path) as archive:
        bad_member = archive.testzip()
        if bad_member is not None:
            raise SystemExit(f"Corrupt ZIP member: {bad_member}")
        for info in archive.infolist():
            extension = Path(info.filename).suffix.lower()
            if extension in {".tif", ".tiff"} and not info.is_dir():
                raster_members.append(info.filename)
            members.append({
                "name": info.filename,
                "compressed_size": info.compress_size,
                "uncompressed_size": info.file_size,
                "extension": extension,
                "is_dir": info.is_dir(),
            })

    if not raster_members:
        raise SystemExit("Official DTM archive contains no TIFF raster")

    inventory = {
        "schema": 1,
        "source": "Paradigm UrbIS Digital Terrain Model 2021",
        "dataset_id": discovery.get("dataset_id"),
        "tile": args.tile,
        "url": url,
        "source_crs_expected": "EPSG:31370",
        "downloaded_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "size_bytes": zip_path.stat().st_size,
        "sha256": sha256_file(zip_path),
        "raster_members": raster_members,
        "members": members,
        "policy": "The official DTM ZIP/TIFF is inspected in CI only and is not committed. This inventory pins provenance, checksum and archive structure for deterministic terrain conversion.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("URBIS_DTM_TILE_OK", args.tile, zip_path.stat().st_size, inventory["sha256"])
    for member in raster_members:
        print("RASTER", member)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
