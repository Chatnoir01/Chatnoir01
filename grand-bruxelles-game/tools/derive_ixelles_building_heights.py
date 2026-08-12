#!/usr/bin/env python3
"""Derive auditable Ixelles building-height statistics from official UrbIS DSM-DTM.

This tool intentionally records robust statistics and confidence rather than baking a
single guessed height into runtime data. Inputs remain in EPSG:31370 / Belgian
Lambert 72. The authoritative building key is the UrbIS INSPIRE_ID when present.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

EXPECTED_CRS = "EPSG:31370"
MIN_VALID_PIXELS = 16
MIN_PLAUSIBLE_FRACTION = 0.60
PLAUSIBLE_MIN_M = -0.50
PLAUSIBLE_MAX_M = 250.0


def percentile(values: np.ndarray, q: float) -> float | None:
    if values.size == 0:
        return None
    return round(float(np.percentile(values, q)), 3)


def summarize_height_samples(dsm: np.ndarray, dtm: np.ndarray, nodata_dsm: float | None, nodata_dtm: float | None) -> dict:
    """Summarize co-located DSM/DTM samples without hiding suspicious observations."""
    if dsm.shape != dtm.shape:
        raise ValueError("DSM/DTM sample shapes differ")
    dsm = np.asarray(dsm, dtype=np.float64).reshape(-1)
    dtm = np.asarray(dtm, dtype=np.float64).reshape(-1)
    valid = np.isfinite(dsm) & np.isfinite(dtm)
    if nodata_dsm is not None and math.isfinite(float(nodata_dsm)):
        valid &= dsm != float(nodata_dsm)
    if nodata_dtm is not None and math.isfinite(float(nodata_dtm)):
        valid &= dtm != float(nodata_dtm)
    diff = dsm[valid] - dtm[valid]
    plausible_mask = (diff >= PLAUSIBLE_MIN_M) & (diff <= PLAUSIBLE_MAX_M)
    plausible = diff[plausible_mask]
    total = int(dsm.size)
    valid_count = int(diff.size)
    plausible_count = int(plausible.size)
    plausible_fraction = plausible_count / valid_count if valid_count else 0.0
    confidence = "insufficient"
    if plausible_count >= MIN_VALID_PIXELS and plausible_fraction >= MIN_PLAUSIBLE_FRACTION:
        confidence = "high" if plausible_count >= 64 and plausible_fraction >= 0.90 else "medium"
    return {
        "pixel_count_total": total,
        "pixel_count_valid": valid_count,
        "pixel_count_plausible": plausible_count,
        "plausible_fraction_of_valid": round(plausible_fraction, 4),
        "negative_below_noise_count": int(np.count_nonzero(diff < PLAUSIBLE_MIN_M)),
        "over_250m_count": int(np.count_nonzero(diff > PLAUSIBLE_MAX_M)),
        "raw_difference_m": {
            "min": round(float(diff.min()), 3) if valid_count else None,
            "max": round(float(diff.max()), 3) if valid_count else None,
            "p50": percentile(diff, 50),
            "p75": percentile(diff, 75),
            "p90": percentile(diff, 90),
        },
        "plausible_difference_m": {
            "p50": percentile(plausible, 50),
            "p75": percentile(plausible, 75),
            "p90": percentile(plausible, 90),
        },
        "confidence": confidence,
    }


def find_rasters(root: Path, kind: str, expected_tiles: list[str]) -> list[Path]:
    paths = []
    for tile in expected_tiles:
        matches = sorted((root / kind / tile).rglob("*.tif")) + sorted((root / kind / tile).rglob("*.tiff"))
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one {kind.upper()} TIFF for {tile}, found {matches}")
        paths.append(matches[0])
    return paths


def open_mosaic(paths: list[Path]):
    import rasterio
    from rasterio.merge import merge
    datasets = [rasterio.open(path) for path in paths]
    try:
        grid = [(d.width, d.height, tuple(d.transform), d.count) for d in datasets]
        if any(d.count != 1 for d in datasets):
            raise ValueError("Height rasters must be single-band")
        mosaic, transform = merge(datasets)
        nodata = datasets[0].nodata
        return mosaic[0], transform, nodata
    finally:
        for dataset in datasets:
            dataset.close()


def polygon_samples(array: np.ndarray, transform, geometry: dict) -> tuple[np.ndarray, np.ndarray]:
    """Return raster rows/cols whose pixel centers fall inside one GeoJSON geometry."""
    from rasterio.features import geometry_mask, geometry_window
    from rasterio.io import MemoryFile
    import rasterio

    profile = {
        "driver": "GTiff",
        "height": array.shape[0],
        "width": array.shape[1],
        "count": 1,
        "dtype": str(array.dtype),
        "transform": transform,
        "crs": "EPSG:31370",
    }
    with MemoryFile() as memfile:
        with memfile.open(**profile) as dataset:
            try:
                window = geometry_window(dataset, [geometry], pad_x=0, pad_y=0)
            except Exception:
                return np.array([], dtype=np.int64), np.array([], dtype=np.int64)
            row0, col0 = int(window.row_off), int(window.col_off)
            h, w = int(window.height), int(window.width)
            if h <= 0 or w <= 0:
                return np.array([], dtype=np.int64), np.array([], dtype=np.int64)
            row0 = max(0, row0)
            col0 = max(0, col0)
            row1 = min(array.shape[0], row0 + h)
            col1 = min(array.shape[1], col0 + w)
            if row1 <= row0 or col1 <= col0:
                return np.array([], dtype=np.int64), np.array([], dtype=np.int64)
            win = rasterio.windows.Window(col0, row0, col1 - col0, row1 - row0)
            win_transform = rasterio.windows.transform(win, transform)
            mask = geometry_mask([geometry], out_shape=(row1 - row0, col1 - col0), transform=win_transform, invert=True, all_touched=False)
            rr, cc = np.nonzero(mask)
            return rr + row0, cc + col0


def derive(plan_path: Path, cell_root: Path, raster_root: Path) -> dict:
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    if plan.get("source_crs") != EXPECTED_CRS:
        raise ValueError(f"Expected {EXPECTED_CRS}, got {plan.get('source_crs')}")
    tiles = list(plan["expected_1km_tile_codes"])
    dsm, dsm_transform, dsm_nodata = open_mosaic(find_rasters(raster_root, "dsm", tiles))
    dtm, dtm_transform, dtm_nodata = open_mosaic(find_rasters(raster_root, "dtm", tiles))
    if dsm.shape != dtm.shape or tuple(dsm_transform) != tuple(dtm_transform):
        raise ValueError("DSM and DTM mosaics are not exactly aligned")

    records = []
    unique_ids = set()
    confidence_counts = Counter()
    duplicate_memberships = 0
    for cell_id in plan["materialized_cells"]:
        buildings_path = cell_root / cell_id / "raw" / "buildings.geojson"
        collection = json.loads(buildings_path.read_text(encoding="utf-8"))
        if collection.get("type") != "FeatureCollection":
            raise ValueError(f"Invalid buildings GeoJSON: {buildings_path}")
        for feature in collection.get("features", []):
            geometry = feature.get("geometry")
            if not geometry or geometry.get("type") not in ("Polygon", "MultiPolygon"):
                continue
            rows, cols = polygon_samples(dsm, dsm_transform, geometry)
            stats = summarize_height_samples(dsm[rows, cols], dtm[rows, cols], dsm_nodata, dtm_nodata)
            props = feature.get("properties") or {}
            inspire_id = props.get("INSPIRE_ID")
            stable_id = inspire_id or feature.get("id")
            if stable_id in unique_ids:
                duplicate_memberships += 1
            unique_ids.add(stable_id)
            confidence_counts[stats["confidence"]] += 1
            terrain_valid = dtm[rows, cols]
            terrain_valid = terrain_valid[np.isfinite(terrain_valid)]
            if dtm_nodata is not None and terrain_valid.size:
                terrain_valid = terrain_valid[terrain_valid != dtm_nodata]
            records.append({
                "cell_id": cell_id,
                "building_id": stable_id,
                "inspire_id": inspire_id,
                "source_feature_id": feature.get("id"),
                "area_m2_urbis": props.get("AREA"),
                "terrain_elevation_m_p50": percentile(terrain_valid.astype(np.float64), 50),
                "height_stats": stats,
            })

    return {
        "schema": 1,
        "format": "grand-bruxelles-ixelles-building-height-stats-v1",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_crs": EXPECTED_CRS,
        "method": "DSM minus DTM sampled at 0.5 m pixel centers inside official UrbIS building footprints",
        "selection_policy": "No runtime building height is baked here. p50/p75/p90 and quality diagnostics are retained for review; insufficient samples remain explicit.",
        "plausibility_window_m": [PLAUSIBLE_MIN_M, PLAUSIBLE_MAX_M],
        "confidence_policy": {
            "minimum_plausible_pixels": MIN_VALID_PIXELS,
            "minimum_plausible_fraction": MIN_PLAUSIBLE_FRACTION,
            "high": "at least 64 plausible pixels and at least 90% of valid samples plausible",
            "medium": "minimum thresholds met but high threshold not met",
            "insufficient": "minimum thresholds not met",
        },
        "materialized_cells": plan["materialized_cells"],
        "expected_1km_tile_codes": tiles,
        "raster_shape": list(dsm.shape),
        "raster_transform": [float(v) for v in dsm_transform[:6]],
        "building_memberships": len(records),
        "unique_building_ids": len(unique_ids),
        "duplicate_cell_memberships": duplicate_memberships,
        "confidence_counts": dict(sorted(confidence_counts.items())),
        "buildings": records,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--cell-root", type=Path, required=True)
    parser.add_argument("--raster-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = derive(args.plan, args.cell_root, args.raster_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("IXELLES_BUILDING_HEIGHT_STATS_READY", result["building_memberships"], result["unique_building_ids"], result["confidence_counts"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
