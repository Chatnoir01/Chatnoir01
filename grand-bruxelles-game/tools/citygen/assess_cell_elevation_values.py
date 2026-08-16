#!/usr/bin/env python3
"""Assess source-value quality of geospatially validated DSM/DTM rasters.

Reads only the selected 500 m cell footprint from the already-extracted rasters.
NoData masks are preserved and values are promoted to float64 before statistics,
avoiding the historic extreme-float32 NoData/mosaic failure. This produces source
evidence only; runtime terrain and building-height gates remain false.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-elevation-value-evidence-v1"
RASTER_FORMAT = "grand-bruxelles-cell-elevation-raster-validation-v1"
MIN_VALID_SAMPLES = 100
MIN_VALID_RATIO = 0.95
MIN_DTM_SPAN_M = 0.01
MAX_SEVERE_NEGATIVE_DELTA_RATIO = 0.10


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def _unique_tiff(extract_root: Path, kind: str, tile: str, filename: str) -> Path:
    matches = sorted((extract_root / kind / tile).rglob(filename))
    if len(matches) != 1:
        raise ValueError(f"{kind}/{tile}: expected one extracted TIFF named {filename}, found {matches}")
    return matches[0]


def _summary(values: Any, total_samples: int) -> dict[str, Any]:
    import numpy as np  # type: ignore
    array = np.asarray(values, dtype="float64")
    array = array[np.isfinite(array)]
    count = int(array.size)
    ratio = float(count / total_samples) if total_samples > 0 else 0.0
    if count == 0:
        return {"valid_samples": 0, "total_samples": total_samples, "valid_ratio": ratio}
    percentiles = np.percentile(array, [1, 5, 25, 50, 75, 95, 99])
    return {
        "valid_samples": count,
        "total_samples": int(total_samples),
        "valid_ratio": ratio,
        "min_m": float(array.min()),
        "max_m": float(array.max()),
        "mean_m": float(array.mean()),
        "p01_m": float(percentiles[0]),
        "p05_m": float(percentiles[1]),
        "p25_m": float(percentiles[2]),
        "p50_m": float(percentiles[3]),
        "p75_m": float(percentiles[4]),
        "p95_m": float(percentiles[5]),
        "p99_m": float(percentiles[6]),
        "span_m": float(array.max() - array.min()),
    }


def assess_quality(dtm: dict[str, Any], dsm: dict[str, Any], delta: dict[str, Any]) -> tuple[bool, bool, list[str]]:
    failures: list[str] = []
    for kind, stats in (("dtm", dtm), ("dsm", dsm), ("delta", delta)):
        if int(stats.get("valid_samples", 0)) < MIN_VALID_SAMPLES:
            failures.append(f"{kind}_insufficient_valid_samples")
        if float(stats.get("valid_ratio", 0.0)) < MIN_VALID_RATIO:
            failures.append(f"{kind}_valid_ratio_below_{MIN_VALID_RATIO}")
    if dtm.get("min_m") is not None and (float(dtm["min_m"]) < -100.0 or float(dtm.get("max_m", 0.0)) > 500.0):
        failures.append("dtm_values_outside_broad_physical_guardrail")
    if dsm.get("min_m") is not None and (float(dsm["min_m"]) < -100.0 or float(dsm.get("max_m", 0.0)) > 750.0):
        failures.append("dsm_values_outside_broad_physical_guardrail")
    if float(dtm.get("span_m", 0.0)) <= MIN_DTM_SPAN_M:
        failures.append("dtm_degenerate_or_nearly_constant")
    severe_negative = float(delta.get("severe_negative_ratio", 1.0))
    if severe_negative > MAX_SEVERE_NEGATIVE_DELTA_RATIO:
        failures.append("dsm_minus_dtm_severe_negative_ratio_too_high")
    terrain_ready = not any(name.startswith("dtm_") for name in failures)
    height_pair_ready = not failures
    return terrain_ready, height_pair_ready, failures


def _collect(validation: dict[str, Any], extract_root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    try:
        import numpy as np  # type: ignore
        import rasterio  # type: ignore
        from rasterio.windows import from_bounds  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy and rasterio are required for elevation value assessment") from exc

    bbox = validation.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError("raster validation cell bbox missing")
    cell_min_e, cell_min_n, cell_max_e, cell_max_n = [float(v) for v in bbox]
    dsm_rows = {row["tile"]: row for row in (validation.get("dsm") or {}).get("rasters", [])}
    dtm_rows = {row["tile"]: row for row in (validation.get("dtm") or {}).get("rasters", [])}
    if set(dsm_rows) != set(dtm_rows) or not dsm_rows:
        raise ValueError("DSM/DTM validated tile sets missing or different")

    dtm_values: list[Any] = []
    dsm_values: list[Any] = []
    delta_values: list[Any] = []
    dtm_total = dsm_total = delta_total = 0
    severe_negative_count = 0
    delta_valid_count = 0

    for tile in sorted(dsm_rows):
        dsm_meta = dsm_rows[tile]["raster"]
        dtm_meta = dtm_rows[tile]["raster"]
        dsm_path = _unique_tiff(extract_root, "dsm", tile, dsm_meta["filename"])
        dtm_path = _unique_tiff(extract_root, "dtm", tile, dtm_meta["filename"])
        with rasterio.open(dsm_path) as dsm_src, rasterio.open(dtm_path) as dtm_src:
            left = max(cell_min_e, float(dsm_src.bounds.left))
            right = min(cell_max_e, float(dsm_src.bounds.right))
            bottom = max(cell_min_n, float(dsm_src.bounds.bottom))
            top = min(cell_max_n, float(dsm_src.bounds.top))
            if not (left < right and bottom < top):
                continue
            dsm_window = from_bounds(left, bottom, right, top, transform=dsm_src.transform).round_offsets().round_lengths()
            dtm_window = from_bounds(left, bottom, right, top, transform=dtm_src.transform).round_offsets().round_lengths()
            dsm_arr = dsm_src.read(1, window=dsm_window, masked=True).astype("float64")
            dtm_arr = dtm_src.read(1, window=dtm_window, masked=True).astype("float64")
            if dsm_arr.shape != dtm_arr.shape:
                raise ValueError(f"{tile}: aligned raster windows produced different shapes")
            combined_mask = np.ma.getmaskarray(dsm_arr) | np.ma.getmaskarray(dtm_arr)
            dsm_plain = np.asarray(dsm_arr.filled(np.nan), dtype="float64")
            dtm_plain = np.asarray(dtm_arr.filled(np.nan), dtype="float64")
            valid_dsm = (~np.ma.getmaskarray(dsm_arr)) & np.isfinite(dsm_plain)
            valid_dtm = (~np.ma.getmaskarray(dtm_arr)) & np.isfinite(dtm_plain)
            pair_valid = (~combined_mask) & np.isfinite(dsm_plain) & np.isfinite(dtm_plain)
            dtm_values.append(dtm_plain[valid_dtm]); dsm_values.append(dsm_plain[valid_dsm])
            delta = dsm_plain - dtm_plain
            delta_values.append(delta[pair_valid])
            dtm_total += int(dtm_arr.size); dsm_total += int(dsm_arr.size); delta_total += int(delta.size)
            valid_delta = delta[pair_valid]
            delta_valid_count += int(valid_delta.size)
            severe_negative_count += int(np.count_nonzero(valid_delta < -2.0))

    if not dtm_values:
        raise ValueError("cell bbox does not intersect any validated elevation raster")
    dtm_flat = np.concatenate(dtm_values) if dtm_values else np.array([], dtype="float64")
    dsm_flat = np.concatenate(dsm_values) if dsm_values else np.array([], dtype="float64")
    delta_flat = np.concatenate(delta_values) if delta_values else np.array([], dtype="float64")
    dtm_stats = _summary(dtm_flat, dtm_total)
    dsm_stats = _summary(dsm_flat, dsm_total)
    delta_stats = _summary(delta_flat, delta_total)
    delta_stats["severe_negative_threshold_m"] = -2.0
    delta_stats["severe_negative_ratio"] = float(severe_negative_count / delta_valid_count) if delta_valid_count else 1.0
    return dtm_stats, dsm_stats, delta_stats


def build(validation_path: Path, extract_root: Path) -> dict[str, Any]:
    validation = _read(validation_path)
    if validation.get("format") != RASTER_FORMAT or validation.get("crs") != "EPSG:31370":
        raise ValueError("unsupported elevation raster-validation manifest")
    dtm_stats, dsm_stats, delta_stats = _collect(validation, extract_root)
    terrain_source_ready, height_pair_ready, failures = assess_quality(dtm_stats, dsm_stats, delta_stats)
    result = {
        "format": FORMAT,
        "cell_id": validation.get("cell_id"),
        "crs": "EPSG:31370",
        "bbox": validation.get("bbox"),
        "dtm": dtm_stats,
        "dsm": dsm_stats,
        "dsm_minus_dtm": delta_stats,
        "quality_failures": failures,
        "terrain_source_evidence_ready": terrain_source_ready,
        "height_source_pair_ready": height_pair_ready,
        "status": "source_value_quality_validated" if height_pair_ready else "source_value_quality_rejected_or_pending",
        "maturity_effect": {
            "terrain_gate": False,
            "heights_gate": False,
            "reason": "source_values_only_runtime_terrain_and_secondary_height_validation_still_required",
        },
    }
    result["evidence_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster-validation", type=Path, required=True)
    parser.add_argument("--extract-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.raster_validation, args.extract_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_VALUE_EVIDENCE_OK", result["cell_id"], result["terrain_source_evidence_ready"], result["height_source_pair_ready"], result["evidence_digest"])


if __name__ == "__main__":
    main()
