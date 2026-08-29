#!/usr/bin/env python3
"""Derive auditable Ixelles building-height statistics from official UrbIS DSM-DTM."""
from __future__ import annotations

import argparse
import csv
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
MIN_DTM_RANGE_M = 0.25
MIN_POSITIVE_HEIGHT_FRACTION = 0.005


def percentile(values: np.ndarray, q: float) -> float | None:
    if values.size == 0:
        return None
    return round(float(np.percentile(values, q)), 3)


def _paired_valid_mask(dsm: np.ndarray, dtm: np.ndarray, nodata_dsm: float | None, nodata_dtm: float | None) -> np.ndarray:
    if dsm.shape != dtm.shape:
        raise ValueError("DSM/DTM sample shapes differ")
    dsm_arr = np.asarray(dsm, dtype=np.float64)
    dtm_arr = np.asarray(dtm, dtype=np.float64)
    valid = np.isfinite(dsm_arr) & np.isfinite(dtm_arr)
    if nodata_dsm is not None and math.isfinite(float(nodata_dsm)):
        valid &= dsm_arr != float(nodata_dsm)
    if nodata_dtm is not None and math.isfinite(float(nodata_dtm)):
        valid &= dtm_arr != float(nodata_dtm)
    return valid


def validate_height_mosaics(
    dsm: np.ndarray,
    dtm: np.ndarray,
    nodata_dsm: float | None,
    nodata_dtm: float | None,
    *,
    min_dtm_range_m: float = MIN_DTM_RANGE_M,
    min_positive_height_fraction: float = MIN_POSITIVE_HEIGHT_FRACTION,
) -> dict:
    """Reject technically aligned but semantically degenerate height rasters.

    Diagnostics are computed only where both DSM and DTM pixels are valid at the same
    position. This avoids silently pairing unrelated samples when nodata masks differ.
    """
    if dsm.shape != dtm.shape:
        raise ValueError("DSM/DTM mosaics have different shapes")
    dsm_arr = np.asarray(dsm, dtype=np.float64)
    dtm_arr = np.asarray(dtm, dtype=np.float64)
    valid = _paired_valid_mask(dsm_arr, dtm_arr, nodata_dsm, nodata_dtm)
    if not np.any(valid):
        raise ValueError("Height mosaics are degenerate: no paired valid elevation samples")

    dsm_values = dsm_arr[valid]
    dtm_values = dtm_arr[valid]
    dtm_range = float(np.max(dtm_values) - np.min(dtm_values))
    diff = dsm_values - dtm_values
    positive_fraction = float(np.count_nonzero(diff > 0.5) / diff.size)
    height_p95 = float(np.percentile(diff, 95))
    identical_fraction = float(np.count_nonzero(np.isclose(diff, 0.0, atol=1e-4)) / diff.size)

    if dtm_range < min_dtm_range_m:
        raise ValueError(f"Height mosaics are degenerate: DTM range is only {dtm_range:.4f} m")
    if positive_fraction < min_positive_height_fraction or height_p95 <= 0.5:
        raise ValueError(
            "Height mosaics are degenerate: DSM-DTM contains no credible above-ground signal "
            f"(positive_fraction={positive_fraction:.6f}, p95={height_p95:.3f} m)"
        )

    return {
        "dtm_min_m": round(float(np.min(dtm_values)), 3),
        "dtm_max_m": round(float(np.max(dtm_values)), 3),
        "dtm_range_m": round(dtm_range, 3),
        "height_p50_m": round(float(np.percentile(diff, 50)), 3),
        "height_p95_m": round(height_p95, 3),
        "positive_height_fraction": round(positive_fraction, 6),
        "identical_dsm_dtm_fraction": round(identical_fraction, 6),
        "valid_sample_count": int(diff.size),
    }


def summarize_height_samples(dsm: np.ndarray, dtm: np.ndarray, nodata_dsm: float | None, nodata_dtm: float | None) -> dict:
    if dsm.shape != dtm.shape:
        raise ValueError("DSM/DTM sample shapes differ")
    dsm = np.asarray(dsm, dtype=np.float64).reshape(-1)
    dtm = np.asarray(dtm, dtype=np.float64).reshape(-1)
    valid = _paired_valid_mask(dsm, dtm, nodata_dsm, nodata_dtm)
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
            "p50": percentile(diff, 50), "p75": percentile(diff, 75), "p90": percentile(diff, 90),
        },
        "plausible_difference_m": {
            "p50": percentile(plausible, 50), "p75": percentile(plausible, 75), "p90": percentile(plausible, 90),
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
        if any(d.count != 1 for d in datasets):
            raise ValueError("Height rasters must be single-band")
        # UrbIS uses the float32 minimum as nodata. rasterio.merge cannot safely use
        # that sentinel as a float32 destination fill value and may produce a zeroed
        # mosaic. Promote the destination to float64 and use NaN as the output nodata;
        # source masks still honour each TIFF's authoritative nodata value.
        mosaic, transform = merge(datasets, nodata=np.nan, dtype="float64")
        return mosaic[0], transform, float("nan")
    finally:
        for dataset in datasets:
            dataset.close()


def polygon_samples(array: np.ndarray, transform, geometry: dict) -> tuple[np.ndarray, np.ndarray]:
    from rasterio.features import geometry_mask, geometry_window
    from rasterio.io import MemoryFile
    import rasterio
    profile = {"driver": "GTiff", "height": array.shape[0], "width": array.shape[1], "count": 1,
               "dtype": str(array.dtype), "transform": transform, "crs": EXPECTED_CRS}
    with MemoryFile() as memfile:
        with memfile.open(**profile) as dataset:
            try:
                window = geometry_window(dataset, [geometry], pad_x=0, pad_y=0)
            except Exception:
                return np.array([], dtype=np.int64), np.array([], dtype=np.int64)
            row0, col0 = max(0, int(window.row_off)), max(0, int(window.col_off))
            row1 = min(array.shape[0], int(window.row_off + window.height))
            col1 = min(array.shape[1], int(window.col_off + window.width))
            if row1 <= row0 or col1 <= col0:
                return np.array([], dtype=np.int64), np.array([], dtype=np.int64)
            win = rasterio.windows.Window(col0, row0, col1 - col0, row1 - row0)
            win_transform = rasterio.windows.transform(win, transform)
            mask = geometry_mask([geometry], out_shape=(row1-row0, col1-col0), transform=win_transform,
                                 invert=True, all_touched=False)
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
    mosaic_diagnostics = validate_height_mosaics(dsm, dtm, dsm_nodata, dtm_nodata)
    records, unique_ids = [], set()
    confidence_counts, duplicate_memberships = Counter(), 0
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
            terrain = np.asarray(dtm[rows, cols], dtype=np.float64)
            paired_valid = _paired_valid_mask(np.asarray(dsm[rows, cols], dtype=np.float64), terrain, dsm_nodata, dtm_nodata)
            terrain_valid = terrain[paired_valid]
            records.append({"cell_id": cell_id, "building_id": stable_id, "inspire_id": inspire_id,
                            "source_feature_id": feature.get("id"), "area_m2_urbis": props.get("AREA"),
                            "terrain_elevation_m_p50": percentile(terrain_valid.astype(np.float64), 50),
                            "height_stats": stats})
    return {
        "schema": 1, "format": "grand-bruxelles-ixelles-building-height-stats-v2",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_crs": EXPECTED_CRS,
        "method": "DSM minus DTM sampled at 0.5 m pixel centers inside official UrbIS building footprints",
        "selection_policy": "No runtime height is baked here. p50/p75/p90 and diagnostics are retained; insufficient samples remain explicit.",
        "plausibility_window_m": [PLAUSIBLE_MIN_M, PLAUSIBLE_MAX_M],
        "mosaic_quality_gate": mosaic_diagnostics,
        "confidence_policy": {"minimum_plausible_pixels": MIN_VALID_PIXELS,
                              "minimum_plausible_fraction": MIN_PLAUSIBLE_FRACTION,
                              "high": "at least 64 plausible pixels and at least 90% of valid samples plausible",
                              "medium": "minimum thresholds met but high threshold not met",
                              "insufficient": "minimum thresholds not met"},
        "materialized_cells": plan["materialized_cells"], "expected_1km_tile_codes": tiles,
        "raster_shape": list(dsm.shape), "raster_transform": [float(v) for v in dsm_transform[:6]],
        "building_memberships": len(records), "unique_building_ids": len(unique_ids),
        "duplicate_cell_memberships": duplicate_memberships,
        "confidence_counts": dict(sorted(confidence_counts.items())), "buildings": records,
    }


def compact_summary(result: dict) -> dict:
    return {k: v for k, v in result.items() if k != "buildings"} | {
        "detail_storage": "Per-building rows are published as CSV; full nested JSON remains a CI artifact only."
    }


def write_csv(result: dict, path: Path) -> None:
    fields = ["cell_id", "building_id", "area_m2_urbis", "terrain_elevation_m_p50", "confidence",
              "pixel_count_valid", "pixel_count_plausible", "plausible_fraction_of_valid",
              "height_p50_m", "height_p75_m", "height_p90_m", "negative_below_noise_count", "over_250m_count"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for b in result["buildings"]:
            h, p = b["height_stats"], b["height_stats"]["plausible_difference_m"]
            writer.writerow({"cell_id": b["cell_id"], "building_id": b["building_id"],
                             "area_m2_urbis": b["area_m2_urbis"], "terrain_elevation_m_p50": b["terrain_elevation_m_p50"],
                             "confidence": h["confidence"], "pixel_count_valid": h["pixel_count_valid"],
                             "pixel_count_plausible": h["pixel_count_plausible"],
                             "plausible_fraction_of_valid": h["plausible_fraction_of_valid"],
                             "height_p50_m": p["p50"], "height_p75_m": p["p75"], "height_p90_m": p["p90"],
                             "negative_below_noise_count": h["negative_below_noise_count"],
                             "over_250m_count": h["over_250m_count"]})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--cell-root", type=Path, required=True)
    parser.add_argument("--raster-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="Full nested JSON, normally kept as CI artifact")
    parser.add_argument("--summary-output", type=Path)
    parser.add_argument("--csv-output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = derive(args.plan, args.cell_root, args.raster_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
    if args.summary_output:
        args.summary_output.parent.mkdir(parents=True, exist_ok=True)
        args.summary_output.write_text(json.dumps(compact_summary(result), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.csv_output:
        write_csv(result, args.csv_output)
    print("IXELLES_BUILDING_HEIGHT_STATS_READY", result["building_memberships"], result["unique_building_ids"], result["confidence_counts"], result["mosaic_quality_gate"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
