#!/usr/bin/env python3
"""Validate geospatial DSM/DTM raster evidence for one CityGen cell.

Consumes archive-integrity manifests plus the downloaded ZIP cache from the same
scheduled pass. It verifies recorded hashes, safely extracts source packages,
opens the TIFFs with rasterio, validates CRS/bounds/resolution/geotransform, and
requires DSM/DTM alignment per tile. It still does not flip terrain/heights gates:
value-quality and building/terrain derivation remain separate evidence stages.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import stat
import urllib.parse
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

FORMAT = "grand-bruxelles-cell-elevation-raster-validation-v1"
ARCHIVE_FORMAT = "grand-bruxelles-cell-elevation-archive-validation-v1"
CRS_EPSG = 31370


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def tile_bbox(tile: str) -> tuple[int, int, int, int]:
    if len(tile) != 6 or not tile.isdigit():
        raise ValueError(f"invalid 1 km tile code: {tile}")
    e = int(tile[:3]) * 1000
    n = int(tile[3:]) * 1000
    return e, n, e + 1000, n + 1000


def validate_raster_metadata(tile: str, meta: dict[str, Any], tolerance_m: float = 0.25) -> None:
    if meta.get("crs_epsg") != CRS_EPSG:
        raise ValueError(f"{tile}: expected EPSG:{CRS_EPSG}, got {meta.get('crs_epsg')}")
    if int(meta.get("width", 0)) <= 0 or int(meta.get("height", 0)) <= 0 or int(meta.get("count", 0)) <= 0:
        raise ValueError(f"{tile}: invalid raster dimensions/bands")
    resolution = meta.get("resolution")
    if not isinstance(resolution, list) or len(resolution) != 2:
        raise ValueError(f"{tile}: raster resolution missing")
    rx, ry = float(resolution[0]), float(resolution[1])
    if not (math.isfinite(rx) and math.isfinite(ry) and rx > 0 and ry > 0):
        raise ValueError(f"{tile}: invalid raster resolution {resolution}")
    if abs(rx - ry) > 1e-9:
        raise ValueError(f"{tile}: non-square pixels unsupported {resolution}")
    bounds = meta.get("bounds")
    if not isinstance(bounds, list) or len(bounds) != 4:
        raise ValueError(f"{tile}: raster bounds missing")
    expected = tile_bbox(tile)
    for got, want in zip([float(v) for v in bounds], expected):
        if abs(got - want) > max(tolerance_m, rx):
            raise ValueError(f"{tile}: raster bounds {bounds} do not match {list(expected)}")
    transform = meta.get("transform")
    if not isinstance(transform, list) or len(transform) != 6:
        raise ValueError(f"{tile}: raster transform missing")
    if [float(v) for v in transform] == [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]:
        raise ValueError(f"{tile}: identity raster transform is not georeferencing")


def validate_pair_alignment(dsm: dict[str, Any], dtm: dict[str, Any]) -> None:
    dsm_by_tile = {row["tile"]: row for row in dsm.get("rasters", [])}
    dtm_by_tile = {row["tile"]: row for row in dtm.get("rasters", [])}
    if set(dsm_by_tile) != set(dtm_by_tile):
        raise ValueError("DSM/DTM raster tile sets differ")
    for tile in sorted(dsm_by_tile):
        a, b = dsm_by_tile[tile]["raster"], dtm_by_tile[tile]["raster"]
        for key in ("width", "height", "crs_epsg", "bounds", "resolution", "transform"):
            if a.get(key) != b.get(key):
                raise ValueError(f"{tile}: DSM/DTM {key} mismatch: {a.get(key)} != {b.get(key)}")


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


def _extract_package(archive_path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive_path) as archive:
        for info in archive.infolist():
            member = _safe_member(info)
            if info.is_dir():
                continue
            target = (destination / Path(*member.parts)).resolve()
            if target != root and root not in target.parents:
                raise ValueError(f"ZIP member escapes extraction root: {info.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)


def _inspect_tiff(path: Path) -> dict[str, Any]:
    try:
        import rasterio  # type: ignore
    except ImportError as exc:
        raise RuntimeError("rasterio>=1.3,<2 is required for elevation raster validation") from exc
    with rasterio.open(path) as src:
        embedded = src.crs.to_epsg() if src.crs else None
        if embedded is not None and embedded != CRS_EPSG:
            raise ValueError(f"raster embeds EPSG:{embedded}, expected EPSG:{CRS_EPSG}: {path.name}")
        transform = [float(v) for v in src.transform[:6]]
        return {
            "filename": path.name,
            "width": int(src.width),
            "height": int(src.height),
            "count": int(src.count),
            "dtype": src.dtypes[0] if src.dtypes else None,
            "embedded_crs_epsg": embedded,
            "crs_epsg": embedded or CRS_EPSG,
            "crs_basis": "embedded_raster" if embedded is not None else "authoritative_source_manifest",
            "bounds": [float(src.bounds.left), float(src.bounds.bottom), float(src.bounds.right), float(src.bounds.top)],
            "resolution": [abs(float(src.transform.a)), abs(float(src.transform.e))],
            "nodata": src.nodata,
            "transform": transform,
        }


def _archive_cache_path(archive_cache: Path, kind: str, tile: str, url: str) -> Path:
    key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    return archive_cache / f"{kind}-{tile}-{key}.zip"


def inspect_kind(validation_path: Path, archive_cache: Path, extract_root: Path) -> dict[str, Any]:
    source = _read(validation_path)
    if source.get("format") != ARCHIVE_FORMAT or source.get("crs") != "EPSG:31370":
        raise ValueError("unsupported elevation archive-validation manifest")
    kind = source.get("kind")
    if kind not in ("dsm", "dtm"):
        raise ValueError("invalid elevation kind")
    rasters: list[dict[str, Any]] = []
    for row in source.get("archives") or []:
        tile = row.get("tile")
        url = row.get("url")
        expected_sha = row.get("sha256")
        tiff_member = ((row.get("zip") or {}).get("tiff_member"))
        if not all(isinstance(v, str) and v for v in (tile, url, expected_sha, tiff_member)):
            raise ValueError("archive-validation row missing tile/url/hash/TIFF member")
        archive_path = _archive_cache_path(archive_cache, kind, tile, url)
        if not archive_path.exists():
            raise ValueError(f"validated archive cache missing: {archive_path.name}")
        actual_sha = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        if actual_sha != expected_sha:
            raise ValueError(f"{tile}: archive SHA-256 changed after validation")
        destination = extract_root / kind / tile
        _extract_package(archive_path, destination)
        tiff_path = destination / Path(*PurePosixPath(tiff_member).parts)
        if not tiff_path.exists():
            raise ValueError(f"{tile}: declared TIFF member missing after safe extraction")
        metadata = _inspect_tiff(tiff_path)
        validate_raster_metadata(tile, metadata)
        rasters.append({"tile": tile, "archive_sha256": expected_sha, "raster": metadata})
    if not rasters:
        raise ValueError("archive validation contains no rasters")
    return {"kind": kind, "rasters": rasters}


def build(dsm_validation: Path, dtm_validation: Path, archive_cache: Path, extract_root: Path) -> dict[str, Any]:
    dsm_source = _read(dsm_validation)
    dtm_source = _read(dtm_validation)
    if dsm_source.get("cell_id") != dtm_source.get("cell_id"):
        raise ValueError("DSM/DTM cell identity mismatch")
    dsm = inspect_kind(dsm_validation, archive_cache, extract_root)
    dtm = inspect_kind(dtm_validation, archive_cache, extract_root)
    validate_pair_alignment(dsm, dtm)
    result = {
        "format": FORMAT,
        "cell_id": dsm_source.get("cell_id"),
        "crs": "EPSG:31370",
        "bbox": dsm_source.get("bbox"),
        "dsm": dsm,
        "dtm": dtm,
        "status": "official_rasters_geospatially_validated_and_pair_aligned",
        "remaining_validation": ["raster_value_quality", "terrain_surface_derivation", "building_height_derivation", "secondary_height_validation"],
        "maturity_effect": {"terrain_gate": False, "heights_gate": False, "reason": "raster_geometry_valid_but_derived_evidence_not_yet_validated"},
    }
    result["validation_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsm-validation", type=Path, required=True)
    parser.add_argument("--dtm-validation", type=Path, required=True)
    parser.add_argument("--archive-cache", type=Path, required=True)
    parser.add_argument("--extract-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.dsm_validation, args.dtm_validation, args.archive_cache, args.extract_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_RASTER_VALIDATION_OK", result["cell_id"], len(result["dsm"]["rasters"]), result["validation_digest"])


if __name__ == "__main__":
    main()
