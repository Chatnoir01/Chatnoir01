#!/usr/bin/env python3
"""Derive per-building metric heights from official DSM minus DTM rasters.

The input building footprints are the committed UrbIS Buildings WFS GeoJSON in
EPSG:31370. DSM and DTM are temporary CI mosaics aligned at 1 m resolution.
For each building, raster pixel centres inside the official footprint are used.
The committed visual height is p75 of valid DSM-DTM samples; p50/p85/p90 and
sample counts are retained for audit and future refinement.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable

import numpy as np
from osgeo import gdal

NODATA_THRESHOLD = -1.0e20
MIN_BUILDING_HEIGHT_M = 2.0
MAX_BUILDING_HEIGHT_M = 120.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--dsm", type=Path, required=True)
    parser.add_argument("--dtm", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def open_raster(path: Path) -> tuple[np.ndarray, tuple[float, ...]]:
    ds = gdal.Open(str(path), gdal.GA_ReadOnly)
    if ds is None:
        raise RuntimeError(f"Unable to open raster: {path}")
    array = ds.GetRasterBand(1).ReadAsArray().astype(np.float32, copy=False)
    gt = ds.GetGeoTransform()
    if abs(gt[2]) > 1e-9 or abs(gt[4]) > 1e-9:
        raise ValueError(f"Rotated rasters are unsupported: {gt}")
    if gt[1] <= 0 or gt[5] >= 0:
        raise ValueError(f"Expected north-up positive-X/negative-Y geotransform: {gt}")
    return array, gt


def iter_positions(coords) -> Iterable[tuple[float, float]]:
    if isinstance(coords, list):
        if len(coords) >= 2 and isinstance(coords[0], (int, float)) and isinstance(coords[1], (int, float)):
            yield float(coords[0]), float(coords[1])
        else:
            for child in coords:
                yield from iter_positions(child)


def geometry_envelope(geometry: dict) -> tuple[float, float, float, float] | None:
    points = list(iter_positions(geometry.get("coordinates", [])))
    if not points:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def pixel_window(envelope: tuple[float, float, float, float], gt: tuple[float, ...], shape: tuple[int, int]) -> tuple[int, int, int, int] | None:
    min_x, min_y, max_x, max_y = envelope
    rows, cols = shape
    col0 = int(math.floor((min_x - gt[0]) / gt[1])) - 1
    col1 = int(math.ceil((max_x - gt[0]) / gt[1])) + 1
    row0 = int(math.floor((gt[3] - max_y) / abs(gt[5]))) - 1
    row1 = int(math.ceil((gt[3] - min_y) / abs(gt[5]))) + 1
    col0 = max(0, col0)
    col1 = min(cols, col1)
    row0 = max(0, row0)
    row1 = min(rows, row1)
    if row1 <= row0 or col1 <= col0:
        return None
    return row0, row1, col0, col1


def point_in_ring(xs: np.ndarray, ys: np.ndarray, ring: list) -> np.ndarray:
    if len(ring) < 3:
        return np.zeros(xs.shape, dtype=bool)
    points = [(float(p[0]), float(p[1])) for p in ring if isinstance(p, list) and len(p) >= 2]
    if len(points) < 3:
        return np.zeros(xs.shape, dtype=bool)
    inside = np.zeros(xs.shape, dtype=bool)
    xj, yj = points[-1]
    eps = 1e-20
    for xi, yi in points:
        crossing = ((yi > ys) != (yj > ys)) & (
            xs < ((xj - xi) * (ys - yi) / ((yj - yi) + eps) + xi)
        )
        inside ^= crossing
        xj, yj = xi, yi
    return inside


def polygon_mask(xs: np.ndarray, ys: np.ndarray, rings: list) -> np.ndarray:
    if not rings:
        return np.zeros(xs.shape, dtype=bool)
    mask = point_in_ring(xs, ys, rings[0])
    for hole in rings[1:]:
        mask &= ~point_in_ring(xs, ys, hole)
    return mask


def geometry_mask(xs: np.ndarray, ys: np.ndarray, geometry: dict) -> np.ndarray:
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if kind == "Polygon":
        return polygon_mask(xs, ys, coords)
    if kind == "MultiPolygon":
        mask = np.zeros(xs.shape, dtype=bool)
        for polygon in coords:
            mask |= polygon_mask(xs, ys, polygon)
        return mask
    return np.zeros(xs.shape, dtype=bool)


def percentile(values: np.ndarray, q: float) -> float:
    return float(np.percentile(values, q))


def quality(sample_count: int, p50: float, p90: float) -> str:
    spread = p90 - p50
    if sample_count >= 40 and spread <= 5.0:
        return "high"
    if sample_count >= 12 and spread <= 10.0:
        return "medium"
    if sample_count >= 4:
        return "low"
    return "insufficient"


def main() -> int:
    args = parse_args()
    document = json.loads(args.buildings.read_text(encoding="utf-8"))
    features = document.get("features", [])
    dsm, dsm_gt = open_raster(args.dsm)
    dtm, dtm_gt = open_raster(args.dtm)
    if dsm.shape != dtm.shape or any(abs(a - b) > 1e-9 for a, b in zip(dsm_gt, dtm_gt)):
        raise ValueError(f"DSM/DTM grids are not aligned: DSM {dsm.shape} {dsm_gt}; DTM {dtm.shape} {dtm_gt}")

    output_records = []
    counts = {"high": 0, "medium": 0, "low": 0, "insufficient": 0, "outside": 0}
    heights = []

    for feature_index, feature in enumerate(features):
        geometry = feature.get("geometry") or {}
        envelope = geometry_envelope(geometry)
        props = feature.get("properties") or {}
        inspire_id = props.get("INSPIRE_ID")
        area_m2 = props.get("AREA")
        base_record = {
            "feature_index": feature_index,
            "inspire_id": inspire_id,
            "area_m2": area_m2,
        }
        if envelope is None:
            output_records.append(base_record | {"height_m": None, "quality": "outside", "sample_count": 0})
            counts["outside"] += 1
            continue
        window = pixel_window(envelope, dsm_gt, dsm.shape)
        if window is None:
            output_records.append(base_record | {"height_m": None, "quality": "outside", "sample_count": 0})
            counts["outside"] += 1
            continue
        row0, row1, col0, col1 = window
        cols = np.arange(col0, col1, dtype=np.float64)
        rows = np.arange(row0, row1, dtype=np.float64)
        x_values = dsm_gt[0] + (cols + 0.5) * dsm_gt[1]
        y_values = dsm_gt[3] + (rows + 0.5) * dsm_gt[5]
        xs, ys = np.meshgrid(x_values, y_values)
        footprint = geometry_mask(xs, ys, geometry)

        dsm_window = dsm[row0:row1, col0:col1]
        dtm_window = dtm[row0:row1, col0:col1]
        difference = dsm_window - dtm_window
        valid = (
            footprint
            & np.isfinite(dsm_window)
            & np.isfinite(dtm_window)
            & (dsm_window > NODATA_THRESHOLD)
            & (dtm_window > NODATA_THRESHOLD)
            & np.isfinite(difference)
            & (difference >= MIN_BUILDING_HEIGHT_M)
            & (difference <= MAX_BUILDING_HEIGHT_M)
        )
        values = difference[valid]
        ground_values = dtm_window[valid]
        roof_values = dsm_window[valid]
        if values.size < 4:
            output_records.append(base_record | {
                "height_m": None,
                "quality": "insufficient",
                "sample_count": int(values.size),
            })
            counts["insufficient"] += 1
            continue

        p50 = percentile(values, 50)
        p75 = percentile(values, 75)
        p85 = percentile(values, 85)
        p90 = percentile(values, 90)
        selected = p75
        q = quality(int(values.size), p50, p90)
        counts[q] += 1
        heights.append(selected)
        output_records.append(base_record | {
            "height_m": round(selected, 3),
            "height_method": "p75_dsm_minus_dtm_inside_urbis_footprint",
            "quality": q,
            "sample_count": int(values.size),
            "p50_m": round(p50, 3),
            "p75_m": round(p75, 3),
            "p85_m": round(p85, 3),
            "p90_m": round(p90, 3),
            "spread_p90_p50_m": round(p90 - p50, 3),
            "ground_median_abs_m": round(float(np.median(ground_values)), 3),
            "surface_median_abs_m": round(float(np.median(roof_values)), 3),
        })

        if (feature_index + 1) % 1000 == 0:
            print("HEIGHT_PROGRESS", feature_index + 1, "/", len(features))

    result = {
        "schema": 1,
        "format": "grand-bruxelles-building-heights-dsm-v1",
        "source_crs": "EPSG:31370",
        "source_buildings": "Paradigm UrbIS Buildings WFS",
        "source_dsm": "Paradigm UrbIS Digital Surface Model 2021",
        "source_dtm": "Paradigm UrbIS Digital Terrain Model 2021",
        "raster_resolution_m": abs(float(dsm_gt[1])),
        "selection_method": "p75 of valid per-pixel DSM-DTM heights whose pixel centres fall inside the official building footprint",
        "valid_height_range_m": [MIN_BUILDING_HEIGHT_M, MAX_BUILDING_HEIGHT_M],
        "feature_count": len(features),
        "quality_counts": counts,
        "derived_height_count": len(heights),
        "derived_height_min_m": min(heights) if heights else None,
        "derived_height_max_m": max(heights) if heights else None,
        "derived_height_median_m": float(np.median(np.asarray(heights))) if heights else None,
        "records": output_records,
        "notes": "This is a remote-sensing derived building surface height, not a cadastral architectural height. p75 is selected to reduce isolated tree/chimney/antenna outliers while preserving real variation. Raw p50/p85/p90 remain available for auditing/refinement.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_BUILDING_HEIGHTS_OK", {
        "features": len(features),
        "derived": len(heights),
        "quality": counts,
        "min": result["derived_height_min_m"],
        "median": result["derived_height_median_m"],
        "max": result["derived_height_max_m"],
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
