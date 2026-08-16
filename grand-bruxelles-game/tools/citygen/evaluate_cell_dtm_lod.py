#!/usr/bin/env python3
"""Evaluate source-faithful DTM terrain LOD candidates for one CityGen cell.

The official DTM remains the source of truth. Candidate grids are sampled from the
validated source raster, reconstructed back at source pixel centres, and compared by
vertical error. This stage is evidence only: it never runtime-approves terrain.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable

FORMAT = "grand-bruxelles-cell-dtm-lod-evidence-v1"
RASTER_FORMAT = "grand-bruxelles-cell-elevation-raster-validation-v1"
VALUE_FORMAT = "grand-bruxelles-cell-elevation-value-evidence-v1"
CRS = "EPSG:31370"
DEFAULT_RESOLUTIONS_M = (1.0, 2.0, 4.0, 8.0)
DEFAULT_P95_THRESHOLD_M = 0.15
RUNTIME_GATES = ["seams", "normals", "collisions", "streaming", "performance", "photo_match"]


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def bilinear_sample(array: Any, transform: Any, xs: Any, ys: Any) -> Any:
    """NaN-aware bilinear sample of a north-up raster at world coordinates."""
    import numpy as np  # type: ignore

    if transform.b != 0 or transform.d != 0 or transform.a <= 0 or transform.e >= 0:
        raise ValueError("expected north-up raster transform with positive X and negative Y pixel size")
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


def _source_pixels_in_bbox(array: Any, transform: Any, bbox: tuple[float, float, float, float]) -> tuple[Any, Any, Any]:
    import numpy as np  # type: ignore

    west, south, east, north = bbox
    xs = transform.c + (np.arange(array.shape[1]) + 0.5) * transform.a
    ys = transform.f + (np.arange(array.shape[0]) + 0.5) * transform.e
    cols = np.where((xs >= west) & (xs < east))[0]
    rows = np.where((ys >= south) & (ys < north))[0]
    if rows.size == 0 or cols.size == 0:
        raise ValueError(f"no source DTM pixels intersect cell bbox {bbox}")
    rr, cc = np.meshgrid(rows, cols, indexing="ij")
    x = transform.c + (cc.reshape(-1) + 0.5) * transform.a
    y = transform.f + (rr.reshape(-1) + 0.5) * transform.e
    values = array[rr, cc].reshape(-1).astype(np.float64)
    return x, y, values


def _make_coarse_grid(array: Any, source_transform: Any, bbox: tuple[float, float, float, float], resolution_m: float) -> tuple[Any, Any]:
    import numpy as np  # type: ignore
    from affine import Affine  # type: ignore

    west, south, east, north = bbox
    width_f = (east - west) / resolution_m
    height_f = (north - south) / resolution_m
    width = int(round(width_f))
    height = int(round(height_f))
    if width <= 1 or height <= 1 or not math.isclose(width * resolution_m, east - west, abs_tol=1e-6) or not math.isclose(height * resolution_m, north - south, abs_tol=1e-6):
        raise ValueError(f"candidate resolution {resolution_m:g}m does not tile the cell bbox exactly")
    transform = Affine(resolution_m, 0.0, west, 0.0, -resolution_m, north)
    rows = np.arange(height)
    cols = np.arange(width)
    rr, cc = np.meshgrid(rows, cols, indexing="ij")
    xs = transform.c + (cc.reshape(-1) + 0.5) * transform.a
    ys = transform.f + (rr.reshape(-1) + 0.5) * transform.e
    sampled = bilinear_sample(array, source_transform, xs, ys).reshape(height, width)
    return sampled, transform


def _error_metrics(source: Any, reconstructed: Any) -> dict[str, Any]:
    import numpy as np  # type: ignore

    paired = np.isfinite(source) & np.isfinite(reconstructed)
    paired_count = int(np.count_nonzero(paired))
    if paired_count == 0:
        raise ValueError("no paired terrain samples available for LOD error measurement")
    error = reconstructed[paired] - source[paired]
    abs_error = np.abs(error)
    return {
        "paired_samples": paired_count,
        "source_min_m": round(float(np.min(source[paired])), 5),
        "source_max_m": round(float(np.max(source[paired])), 5),
        "mean_bias_m": round(float(np.mean(error)), 6),
        "rmse_m": round(float(np.sqrt(np.mean(error * error))), 6),
        "p50_abs_error_m": round(float(np.percentile(abs_error, 50)), 6),
        "p95_abs_error_m": round(float(np.percentile(abs_error, 95)), 6),
        "max_abs_error_m": round(float(np.max(abs_error)), 6),
    }


def evaluate_array(array: Any, transform: Any, bbox: tuple[float, float, float, float], resolutions_m: Iterable[float] = DEFAULT_RESOLUTIONS_M) -> dict[str, Any]:
    import numpy as np  # type: ignore

    source_pixel_size = abs(float(transform.a))
    if not math.isclose(source_pixel_size, abs(float(transform.e)), rel_tol=0.0, abs_tol=1e-9):
        raise ValueError("DTM source pixels must be square")
    xs, ys, source = _source_pixels_in_bbox(array, transform, bbox)
    finite_source = source[np.isfinite(source)]
    if finite_source.size == 0 or float(np.max(finite_source) - np.min(finite_source)) < 0.01:
        raise ValueError("DTM source inside cell is empty or degenerate")
    levels: list[dict[str, Any]] = []
    source_sample_count = int(finite_source.size)
    for raw_resolution in resolutions_m:
        resolution = float(raw_resolution)
        if resolution < source_pixel_size:
            raise ValueError("LOD resolution cannot be finer than the official source pixel size")
        coarse, coarse_transform = _make_coarse_grid(array, transform, bbox, resolution)
        reconstructed = bilinear_sample(coarse, coarse_transform, xs, ys)
        metrics = _error_metrics(source, reconstructed)
        vertex_count = int(coarse.shape[0] * coarse.shape[1])
        levels.append({
            "resolution_m": resolution,
            "grid_shape": [int(coarse.shape[0]), int(coarse.shape[1])],
            "vertex_count": vertex_count,
            "source_sample_count": source_sample_count,
            "sample_reduction_ratio": round(float(source_sample_count / vertex_count), 3) if vertex_count else None,
            **metrics,
        })
    return {"source_pixel_size_m": source_pixel_size, "source_valid_samples": source_sample_count, "levels": levels}


def select_resolution(levels: list[dict[str, Any]], p95_threshold_m: float = DEFAULT_P95_THRESHOLD_M) -> dict[str, Any]:
    if not levels:
        raise ValueError("terrain LOD selection requires at least one evaluated level")
    eligible: list[dict[str, Any]] = []
    for row in levels:
        resolution = float(row.get("resolution_m", 0.0))
        p95 = float(row.get("p95_abs_error_m", math.inf))
        if resolution <= 0 or not math.isfinite(p95):
            raise ValueError("terrain LOD level contains invalid resolution or p95 error")
        if p95 <= p95_threshold_m:
            eligible.append(row)
    selected = max(eligible, key=lambda row: float(row["resolution_m"])) if eligible else None
    blockers: list[str] = []
    if selected is None:
        blockers.append("no_candidate_meets_p95_threshold")
    return {
        "p95_threshold_m": float(p95_threshold_m),
        "selection_policy": "coarsest_candidate_with_p95_at_or_below_threshold",
        "selected_resolution_m": float(selected["resolution_m"]) if selected else None,
        "selected_p95_abs_error_m": float(selected["p95_abs_error_m"]) if selected else None,
        "selected_vertex_count": int(selected["vertex_count"]) if selected and "vertex_count" in selected else None,
        "blockers": blockers,
        "runtime_approved": False,
        "remaining_runtime_gates": list(RUNTIME_GATES),
    }


def _find_dtm_tiffs(raster_validation: dict[str, Any], extract_root: Path) -> list[Path]:
    rows = (raster_validation.get("dtm") or {}).get("rasters") or []
    if not rows:
        raise ValueError("validated DTM raster list is empty")
    paths: list[Path] = []
    for row in sorted(rows, key=lambda item: str(item.get("tile"))):
        tile = str(row.get("tile"))
        filename = str((row.get("raster") or {}).get("filename"))
        matches = sorted((extract_root / "dtm" / tile).rglob(filename))
        if len(matches) != 1:
            raise ValueError(f"dtm/{tile}: expected one extracted TIFF named {filename}, found {matches}")
        paths.append(matches[0])
    return paths


def _open_dtm_mosaic(paths: list[Path]) -> tuple[Any, Any]:
    import numpy as np  # type: ignore
    import rasterio  # type: ignore
    from rasterio.merge import merge  # type: ignore

    datasets = [rasterio.open(path) for path in paths]
    try:
        if any(dataset.count != 1 for dataset in datasets):
            raise ValueError("DTM rasters must be single-band")
        if any(dataset.crs is None or dataset.crs.to_epsg() != 31370 for dataset in datasets):
            raise ValueError("DTM rasters must be EPSG:31370")
        mosaic, transform = merge(datasets, nodata=np.nan, dtype="float64")
        array = np.asarray(mosaic[0], dtype="float64")
        return array, transform
    finally:
        for dataset in datasets:
            dataset.close()


def build(raster_validation_path: Path, value_evidence_path: Path, extract_root: Path, resolutions_m: Iterable[float] = DEFAULT_RESOLUTIONS_M, p95_threshold_m: float = DEFAULT_P95_THRESHOLD_M) -> dict[str, Any]:
    raster_validation = _read(raster_validation_path)
    value_evidence = _read(value_evidence_path)
    if raster_validation.get("format") != RASTER_FORMAT or raster_validation.get("crs") != CRS:
        raise ValueError("unsupported elevation raster validation")
    if value_evidence.get("format") != VALUE_FORMAT or value_evidence.get("crs") != CRS:
        raise ValueError("unsupported elevation value evidence")
    cell_id = raster_validation.get("cell_id")
    if not isinstance(cell_id, str) or value_evidence.get("cell_id") != cell_id:
        raise ValueError("terrain LOD evidence cell identity mismatch")
    if value_evidence.get("terrain_source_evidence_ready") is not True:
        raise ValueError("terrain source value evidence is not ready")
    bbox_raw = raster_validation.get("bbox")
    if not isinstance(bbox_raw, list) or len(bbox_raw) != 4:
        raise ValueError("terrain LOD requires canonical cell bbox")
    bbox = tuple(float(v) for v in bbox_raw)
    if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
        raise ValueError("terrain LOD bbox is invalid")
    paths = _find_dtm_tiffs(raster_validation, extract_root)
    array, transform = _open_dtm_mosaic(paths)
    evaluated = evaluate_array(array, transform, bbox, resolutions_m)
    selection = select_resolution(evaluated["levels"], p95_threshold_m)
    result: dict[str, Any] = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": list(bbox),
        "source": "official_validated_DTM",
        "source_raster_validation_digest": raster_validation.get("validation_digest"),
        "source_value_evidence_digest": value_evidence.get("evidence_digest"),
        "method": "sample_official_DTM_to_candidate_grids_then_bilinearly_reconstruct_at_source_pixel_centres",
        "candidate_resolutions_m": [float(v) for v in resolutions_m],
        "source_pixel_size_m": evaluated["source_pixel_size_m"],
        "source_valid_samples": evaluated["source_valid_samples"],
        "levels": evaluated["levels"],
        "selection": selection,
        "status": "terrain_lod_candidate_selected_pending_runtime_validation" if selection["selected_resolution_m"] is not None else "terrain_lod_no_candidate_pending_review",
        "runtime_approved": False,
        "maturity_effect": {
            "terrain_gate": False,
            "reason": "lod_error_only_seams_normals_collisions_streaming_performance_and_photo_match_still_required",
        },
    }
    result["evidence_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster-validation", type=Path, required=True)
    parser.add_argument("--value-evidence", type=Path, required=True)
    parser.add_argument("--extract-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--resolutions", type=float, nargs="*", default=list(DEFAULT_RESOLUTIONS_M))
    parser.add_argument("--p95-threshold", type=float, default=DEFAULT_P95_THRESHOLD_M)
    args = parser.parse_args()
    result = build(args.raster_validation, args.value_evidence, args.extract_root, tuple(args.resolutions), args.p95_threshold)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_DTM_LOD_OK", result["cell_id"], result["selection"]["selected_resolution_m"], result["evidence_digest"])


if __name__ == "__main__":
    main()
