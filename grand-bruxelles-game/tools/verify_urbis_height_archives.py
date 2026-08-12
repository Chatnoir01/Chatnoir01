#!/usr/bin/env python3
"""Download, hash, and validate official UrbIS DSM/DTM GeoTIFF archives."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

USER_AGENT = "Grand-Bruxelles-Game/1.0 (authoritative height archive validation)"
ALLOWED_HOST = "urbisdownload.datastore.brussels"


def tile_bbox(tile: str) -> tuple[int, int, int, int]:
    if len(tile) != 6 or not tile.isdigit():
        raise ValueError(f"Invalid 1 km tile code: {tile}")
    x = int(tile[:3]) * 1000
    y = int(tile[3:]) * 1000
    return x, y, x + 1000, y + 1000


def validate_source_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != ALLOWED_HOST:
        raise ValueError(f"Height archive must use official HTTPS host {ALLOWED_HOST}: {url}")
    if not parsed.path.lower().endswith(".zip"):
        raise ValueError(f"Height archive must be ZIP: {url}")


def download_with_sha256(url: str, output: Path, max_bytes: int = 2_000_000_000) -> tuple[int, str]:
    validate_source_url(url)
    output.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, output.open("wb") as dst:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"Archive exceeds safety limit ({max_bytes} bytes): {url}")
            digest.update(chunk)
            dst.write(chunk)
    if total == 0:
        raise ValueError(f"Downloaded empty archive: {url}")
    return total, digest.hexdigest()


def safe_tiff_members(archive: Path) -> list[str]:
    with zipfile.ZipFile(archive) as zf:
        members: list[str] = []
        for info in zf.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError(f"Unsafe ZIP member: {info.filename}")
            if info.flag_bits & 0x1:
                raise ValueError(f"Encrypted ZIP member is unsupported: {info.filename}")
            if not info.is_dir() and path.suffix.lower() in (".tif", ".tiff"):
                members.append(info.filename)
        if not members:
            raise ValueError(f"No GeoTIFF found in {archive}")
        return sorted(members)


def extract_member(archive: Path, member: str, destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        info = zf.getinfo(member)
        target = destination / Path(PurePosixPath(info.filename).name)
        with zf.open(info) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        return target


def inspect_geotiff(path: Path) -> dict:
    try:
        import rasterio  # type: ignore
    except ImportError as exc:
        raise RuntimeError("rasterio is required for GeoTIFF validation") from exc
    with rasterio.open(path) as src:
        return {
            "filename": path.name,
            "width": src.width,
            "height": src.height,
            "count": src.count,
            "dtype": src.dtypes[0] if src.dtypes else None,
            "crs_epsg": src.crs.to_epsg() if src.crs else None,
            "bounds": [float(src.bounds.left), float(src.bounds.bottom), float(src.bounds.right), float(src.bounds.top)],
            "resolution": [abs(float(src.transform.a)), abs(float(src.transform.e))],
            "nodata": src.nodata,
            "transform": [float(v) for v in src.transform[:6]],
        }


def validate_geotiff_metadata(tile: str, meta: dict, tolerance_m: float = 0.25) -> None:
    if meta.get("crs_epsg") != 31370:
        raise ValueError(f"{tile}: expected EPSG:31370, got {meta.get('crs_epsg')}")
    if int(meta.get("width", 0)) <= 0 or int(meta.get("height", 0)) <= 0 or int(meta.get("count", 0)) <= 0:
        raise ValueError(f"{tile}: invalid raster dimensions/bands: {meta}")
    rx, ry = [float(x) for x in meta["resolution"]]
    if not (math.isfinite(rx) and math.isfinite(ry) and rx > 0 and ry > 0):
        raise ValueError(f"{tile}: invalid raster resolution: {meta['resolution']}")
    if abs(rx - ry) > 1e-9:
        raise ValueError(f"{tile}: non-square pixels are unsupported: {meta['resolution']}")
    expected = tile_bbox(tile)
    actual = [float(v) for v in meta["bounds"]]
    for got, want in zip(actual, expected):
        if abs(got - want) > max(tolerance_m, rx):
            raise ValueError(f"{tile}: raster bounds {actual} do not match 1 km tile {list(expected)}")


def validate_pair_alignment(dsm: dict, dtm: dict) -> None:
    dsm_by_tile = {item["tile"]: item for item in dsm["archives"]}
    dtm_by_tile = {item["tile"]: item for item in dtm["archives"]}
    if set(dsm_by_tile) != set(dtm_by_tile):
        raise ValueError("DSM/DTM tile sets differ")
    for tile in sorted(dsm_by_tile):
        a, b = dsm_by_tile[tile]["geotiff"], dtm_by_tile[tile]["geotiff"]
        for key in ("width", "height", "crs_epsg", "bounds", "resolution", "transform"):
            if a[key] != b[key]:
                raise ValueError(f"{tile}: DSM/DTM {key} mismatch: {a[key]} != {b[key]}")


def verify_resolution(resolution_path: Path, work_dir: Path) -> dict:
    source = json.loads(resolution_path.read_text(encoding="utf-8"))
    if source.get("source_crs") != "EPSG:31370":
        raise ValueError(f"Unexpected source CRS: {source.get('source_crs')}")
    archives = []
    for item in source["resolved_archives"]:
        tile, url = item["tile"], item["url"]
        if tile not in source["expected_1km_tile_codes"]:
            raise ValueError(f"Unexpected tile in resolution: {tile}")
        archive_path = work_dir / source["kind"] / f"{tile}.zip"
        size, sha256 = download_with_sha256(url, archive_path)
        members = safe_tiff_members(archive_path)
        if len(members) != 1:
            raise ValueError(f"{tile}: expected exactly one GeoTIFF, found {members}")
        tif = extract_member(archive_path, members[0], work_dir / source["kind"] / tile)
        meta = inspect_geotiff(tif)
        validate_geotiff_metadata(tile, meta)
        archives.append({"tile": tile, "url": url, "archive_bytes": size, "sha256": sha256, "geotiff": meta})
    if [x["tile"] for x in archives] != list(source["expected_1km_tile_codes"]):
        raise ValueError("Verified archive order/tile set differs from resolution")
    return {
        "schema": 1,
        "format": "grand-bruxelles-height-archive-validation-v1",
        "kind": source["kind"],
        "source": source["source"],
        "dataset_id": source["dataset_id"],
        "source_crs": source["source_crs"],
        "bbox_epsg31370": source["bbox_epsg31370"],
        "expected_1km_tile_codes": source["expected_1km_tile_codes"],
        "license": source["license"],
        "validated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "archives": archives,
        "status": "official_archives_hashed_and_geotiffs_validated",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsm-resolution", type=Path, required=True)
    parser.add_argument("--dtm-resolution", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--dsm-output", type=Path, required=True)
    parser.add_argument("--dtm-output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dsm = verify_resolution(args.dsm_resolution, args.work_dir)
    dtm = verify_resolution(args.dtm_resolution, args.work_dir)
    validate_pair_alignment(dsm, dtm)
    for output, payload in ((args.dsm_output, dsm), (args.dtm_output, dtm)):
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for kind, payload in (("dsm", dsm), ("dtm", dtm)):
        for item in payload["archives"]:
            print("IXELLES_HEIGHT_ARCHIVE_VALID", kind, item["tile"], item["sha256"], item["geotiff"]["resolution"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
