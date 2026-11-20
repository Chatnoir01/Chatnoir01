#!/usr/bin/env python3
"""Evaluate source-faithful DTM LOD candidates for the five materialized Ixelles cells.

The output is evidence only: it measures reconstruction error against the official
0.5 m UrbIS DTM and does not approve a runtime terrain resolution automatically.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np

EXPECTED_CRS = "EPSG:31370"
CELL_SIZE_M = 500.0
DEFAULT_RESOLUTIONS_M = (1.0, 2.0, 4.0, 8.0)


def bilinear_sample(array: np.ndarray, transform, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """Sample a north-up raster at world coordinates with NaN-aware bilinear weights."""
    if transform.b != 0 or transform.d != 0 or transform.a <= 0 or transform.e >= 0:
        raise ValueError("Expected north-up raster transform with positive X and negative Y pixel size")
    cols = (xs - transform.c) / transform.a - 0.5
    rows = (ys - transform.f) / transform.e - 0.5
    c0 = np.floor(cols).astype(np.int64)
    r0 = np.floor(rows).astype(np.int64)
    dc = cols - c0
    dr = rows - r0
    out = np.full(xs.shape, np.nan, dtype=np.float64)

    valid_bounds = (r0 >= 0) & (c0 >= 0) & (r0 + 1 < array.shape[0]) & (c0 + 1 < array.shape[1])
    if not np.any(valid_bounds):
        return out
    idx = np.where(valid_bounds)[0]
    rr, cc = r0[idx], c0[idx]
    vals = np.stack(
        [array[rr, cc], array[rr, cc + 1], array[rr + 1, cc], array[rr + 1, cc + 1]],
        axis=1,
    ).astype(np.float64)
    weights = np.stack(
        [(1 - dr[idx]) * (1 - dc[idx]), (1 - dr[idx]) * dc[idx], dr[idx] * (1 - dc[idx]), dr[idx] * dc[idx]],
        axis=1,
    )
    finite = np.isfinite(vals)
    weighted = np.where(finite, vals * weights, 0.0)
    denom = np.where(finite, weights, 0.0).sum(axis=1)
    good = denom > 0
    sampled = np.full(idx.shape, np.nan, dtype=np.float64)
    sampled[good] = weighted[good].sum(axis=1) / denom[good]
    out[idx] = sampled
    return out


def cell_bbox(cell_id: str) -> tuple[float, float, float, float]:
    # bxl-e149000-n169000-s500
    parts = cell_id.split("-")
    try:
        east = float(parts[1][1:])
        north = float(parts[2][1:])
        size = float(parts[3][1:])
    except (IndexError, ValueError) as exc:
        raise ValueError(f"Invalid cell id {cell_id!r}") from exc
    if not math.isclose(size, CELL_SIZE_M):
        raise ValueError(f"Expected {CELL_SIZE_M:g} m cell, got {size:g}")
    return east, north, east + size, north + size


def source_pixels_in_bbox(array: np.ndarray, transform, bbox: tuple[float, float, float, float]):
    west, south, east, north = bbox
    xs = transform.c + (np.arange(array.shape[1]) + 0.5) * transform.a
    ys = transform.f + (np.arange(array.shape[0]) + 0.5) * transform.e
    cols = np.where((xs >= west) & (xs < east))[0]
    rows = np.where((ys >= south) & (ys < north))[0]
    if rows.size == 0 or cols.size == 0:
        raise ValueError(f"No source DTM pixels intersect cell bbox {bbox}")
    rr, cc = np.meshgrid(rows, cols, indexing="ij")
    x = transform.c + (cc.reshape(-1) + 0.5) * transform.a
    y = transform.f + (rr.reshape(-1) + 0.5) * transform.e
    values = array[rr, cc].reshape(-1).astype(np.float64)
    return x, y, values


def make_coarse_grid(array: np.ndarray, source_transform, bbox, resolution_m: float):
    from affine import Affine

    west, south, east, north = bbox
    width = int(round((east - west) / resolution_m))
    height = int(round((north - south) / resolution_m))
    if width <= 1 or height <= 1:
        raise ValueError("Terrain LOD grid is too small")
    transform = Affine(resolution_m, 0.0, west, 0.0, -resolution_m, north)
    cols = np.arange(width)
    rows = np.arange(height)
    rr, cc = np.meshgrid(rows, cols, indexing="ij")
    xs = transform.c + (cc.reshape(-1) + 0.5) * transform.a
    ys = transform.f + (rr.reshape(-1) + 0.5) * transform.e
    sampled = bilinear_sample(array, source_transform, xs, ys).reshape(height, width)
    return sampled, transform


def error_metrics(source: np.ndarray, reconstructed: np.ndarray) -> dict:
    paired = np.isfinite(source) & np.isfinite(reconstructed)
    if not np.any(paired):
        raise ValueError("No paired terrain samples available for LOD error measurement")
    error = reconstructed[paired] - source[paired]
    abs_error = np.abs(error)
    return {
        "paired_samples": int(error.size),
        "source_min_m": round(float(np.min(source[paired])), 4),
        "source_max_m": round(float(np.max(source[paired])), 4),
        "mean_bias_m": round(float(np.mean(error)), 5),
        "rmse_m": round(float(np.sqrt(np.mean(error * error))), 5),
        "p50_abs_error_m": round(float(np.percentile(abs_error, 50)), 5),
        "p95_abs_error_m": round(float(np.percentile(abs_error, 95)), 5),
        "max_abs_error_m": round(float(np.max(abs_error)), 5),
    }


def evaluate_cell(array: np.ndarray, transform, cell_id: str, resolutions_m=DEFAULT_RESOLUTIONS_M) -> dict:
    bbox = cell_bbox(cell_id)
    xs, ys, source = source_pixels_in_bbox(array, transform, bbox)
    levels = []
    for resolution in resolutions_m:
        if resolution < abs(transform.a):
            raise ValueError("LOD resolution cannot be finer than the official source pixel size")
        coarse, coarse_transform = make_coarse_grid(array, transform, bbox, float(resolution))
        reconstructed = bilinear_sample(coarse, coarse_transform, xs, ys)
        metrics = error_metrics(source, reconstructed)
        levels.append({
            "resolution_m": float(resolution),
            "grid_shape": [int(coarse.shape[0]), int(coarse.shape[1])],
            **metrics,
        })
    return {
        "cell_id": cell_id,
        "bbox_epsg31370": [bbox[0], bbox[1], bbox[2], bbox[3]],
        "source_pixel_size_m": abs(float(transform.a)),
        "levels": levels,
    }


def evaluate(plan_path: Path, raster_root: Path, resolutions_m=DEFAULT_RESOLUTIONS_M) -> dict:
    # Reuse the already tested extreme-nodata-safe mosaic implementation.
    import importlib.util
    derive_path = Path(__file__).with_name("derive_ixelles_building_heights.py")
    spec = importlib.util.spec_from_file_location("derive_ixelles_building_heights", derive_path)
    derive = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(derive)

    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    if plan.get("source_crs") != EXPECTED_CRS:
        raise ValueError(f"Expected {EXPECTED_CRS}")
    tiles = list(plan["expected_1km_tile_codes"])
    dtm, transform, nodata = derive.open_mosaic(derive.find_rasters(raster_root, "dtm", tiles))
    if np.isfinite(nodata):
        dtm = np.where(dtm == nodata, np.nan, dtm)
    finite = dtm[np.isfinite(dtm)]
    if finite.size == 0 or float(np.max(finite) - np.min(finite)) < 0.25:
        raise ValueError("DTM is semantically degenerate")

    cells = [evaluate_cell(dtm, transform, cell_id, resolutions_m) for cell_id in plan["materialized_cells"]]
    return {
        "schema": 1,
        "format": "grand-bruxelles-ixelles-dtm-lod-evidence-v1",
        "source_crs": EXPECTED_CRS,
        "source": "official UrbIS DTM 2021, 0.5 m pixels",
        "status": "evidence_only_not_runtime_approved",
        "runtime_approved": False,
        "method": "sample official DTM onto candidate grids, bilinearly reconstruct at original pixel centers, measure paired vertical error",
        "candidate_resolutions_m": [float(v) for v in resolutions_m],
        "cells": cells,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--raster-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--resolutions", type=float, nargs="*", default=list(DEFAULT_RESOLUTIONS_M))
    args = parser.parse_args()
    result = evaluate(args.plan, args.raster_root, tuple(args.resolutions))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for cell in result["cells"]:
        print("IXELLES_DTM_LOD_CELL", cell["cell_id"], [(l["resolution_m"], l["p95_abs_error_m"]) for l in cell["levels"]])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
