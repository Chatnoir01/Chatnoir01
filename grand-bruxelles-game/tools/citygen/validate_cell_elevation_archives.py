#!/usr/bin/env python3
"""Download, hash and structurally validate resolved official elevation archives.

This stage proves transport/archive integrity only. It does not trust raster CRS,
bounds, resolution or values yet, and therefore never flips terrain/heights gates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import stat
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

FORMAT = "grand-bruxelles-cell-elevation-archive-validation-v1"
RESOLUTION_FORMAT = "grand-bruxelles-cell-elevation-source-resolution-v1"
OFFICIAL_HOST = "urbisdownload.datastore.brussels"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (authoritative elevation archive validation)"
DEFAULT_MAX_BYTES = 750_000_000


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def validate_source_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != OFFICIAL_HOST:
        raise ValueError(f"elevation archive must use official HTTPS host {OFFICIAL_HOST}: {url}")
    if not parsed.path.lower().endswith(".zip"):
        raise ValueError(f"elevation archive must be ZIP: {url}")


def download_with_sha256(url: str, output: Path, max_bytes: int = DEFAULT_MAX_BYTES) -> tuple[int, str]:
    validate_source_url(url)
    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    output.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=120) as response, output.open("wb") as dst:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise ValueError(f"archive exceeds safety limit ({max_bytes} bytes): {url}")
                digest.update(chunk)
                dst.write(chunk)
    except Exception:
        output.unlink(missing_ok=True)
        raise
    if total == 0:
        output.unlink(missing_ok=True)
        raise ValueError(f"downloaded empty archive: {url}")
    return total, digest.hexdigest()


def _safe_member(info: zipfile.ZipInfo) -> PurePosixPath:
    path = PurePosixPath(info.filename)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe ZIP member: {info.filename}")
    if info.flag_bits & 0x1:
        raise ValueError(f"encrypted ZIP member unsupported: {info.filename}")
    unix_mode = (info.external_attr >> 16) & 0xFFFF
    if unix_mode and stat.S_ISLNK(unix_mode):
        raise ValueError(f"symlink ZIP member unsupported: {info.filename}")
    return path


def inspect_zip(path: Path) -> dict[str, Any]:
    if not zipfile.is_zipfile(path):
        raise ValueError(f"download is not a ZIP archive: {path}")
    files: list[str] = []
    tiffs: list[str] = []
    uncompressed_bytes = 0
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            member = _safe_member(info)
            if info.is_dir():
                continue
            files.append(info.filename)
            uncompressed_bytes += int(info.file_size)
            if member.suffix.lower() in (".tif", ".tiff"):
                tiffs.append(info.filename)
    if len(tiffs) != 1:
        raise ValueError(f"expected exactly one TIFF raster, found {sorted(tiffs)}")
    return {
        "file_count": len(files),
        "tiff_member": tiffs[0],
        "uncompressed_bytes": uncompressed_bytes,
        "members_digest": hashlib.sha256("\n".join(sorted(files)).encode("utf-8")).hexdigest(),
    }


def validate_resolution(resolution_path: Path, work_dir: Path, max_bytes: int = DEFAULT_MAX_BYTES) -> dict[str, Any]:
    source = _read(resolution_path)
    if source.get("format") != RESOLUTION_FORMAT:
        raise ValueError("unsupported elevation resolution format")
    if source.get("crs") != "EPSG:31370":
        raise ValueError("elevation resolution CRS mismatch")
    kind = source.get("kind")
    if kind not in ("dsm", "dtm"):
        raise ValueError("invalid elevation kind")
    expected = source.get("expected_1km_tile_codes")
    resolved = source.get("resolved_archives")
    if not isinstance(expected, list) or not isinstance(resolved, list):
        raise ValueError("resolution tile lists missing")
    by_tile: dict[str, str] = {}
    for row in resolved:
        if not isinstance(row, dict) or not isinstance(row.get("tile"), str) or not isinstance(row.get("url"), str):
            raise ValueError("invalid resolved archive row")
        tile = row["tile"]
        if tile in by_tile:
            raise ValueError(f"duplicate resolved tile: {tile}")
        validate_source_url(row["url"])
        by_tile[tile] = row["url"]
    if sorted(by_tile) != sorted(expected):
        raise ValueError("resolved archive tile set differs from requirements")

    archives: list[dict[str, Any]] = []
    for tile in expected:
        url = by_tile[tile]
        url_key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
        archive_path = work_dir / f"{kind}-{tile}-{url_key}.zip"
        if archive_path.exists():
            size = archive_path.stat().st_size
            if size <= 0 or size > max_bytes:
                archive_path.unlink(missing_ok=True)
                size, sha256 = download_with_sha256(url, archive_path, max_bytes)
            else:
                sha256 = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        else:
            size, sha256 = download_with_sha256(url, archive_path, max_bytes)
        structural = inspect_zip(archive_path)
        archives.append({"tile": tile, "url": url, "archive_bytes": size, "sha256": sha256, "zip": structural})

    result = {
        "format": FORMAT,
        "cell_id": source.get("cell_id"),
        "kind": kind,
        "crs": "EPSG:31370",
        "bbox": source.get("bbox"),
        "dataset_id": source.get("dataset_id"),
        "expected_1km_tile_codes": expected,
        "archives": archives,
        "status": "official_archives_downloaded_hashed_and_zip_structure_validated",
        "remaining_validation": ["raster_crs", "raster_bounds", "pixel_resolution", "geotransform", "dsm_dtm_alignment", "raster_value_quality"],
        "maturity_effect": {"terrain_gate": False, "heights_gate": False, "reason": "archive_integrity_only_raster_not_validated"},
    }
    result["validation_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resolution", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    args = parser.parse_args()
    result = validate_resolution(args.resolution, args.work_dir, args.max_bytes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_ARCHIVE_VALIDATION_OK", result["cell_id"], result["kind"], len(result["archives"]), result["validation_digest"])


if __name__ == "__main__":
    main()
