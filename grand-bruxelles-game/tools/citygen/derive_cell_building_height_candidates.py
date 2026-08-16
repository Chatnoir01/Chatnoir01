#!/usr/bin/env python3
"""Derive conservative per-building height candidates from validated DSM-DTM.

This is evidence generation only. It samples paired DSM/DTM pixels whose centers fall
inside authoritative UrbIS footprints, classifies confidence, and emits a candidate
only for sufficient evidence. No candidate is runtime-approved here; a secondary
independent height validation remains mandatory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-building-height-candidates-v1"
VALUE_FORMAT = "grand-bruxelles-cell-elevation-value-evidence-v1"
FRONTIER_FORMAT = "grand-bruxelles-cell-elevation-candidate-frontier-v1"
RASTER_FORMAT = "grand-bruxelles-cell-elevation-raster-validation-v1"
SOURCE_FORMAT = "grand-bruxelles-urbis-source-cell-v1"
CRS = "EPSG:31370"
MIN_VALID_PIXELS = 16
MIN_PLAUSIBLE_FRACTION = 0.60
HIGH_VALID_PIXELS = 64
HIGH_PLAUSIBLE_FRACTION = 0.90
PLAUSIBLE_MIN_M = -0.50
PLAUSIBLE_MAX_M = 250.0
MIN_CANDIDATE_HEIGHT_M = 1.50
LARGE_SPREAD_M = 20.0


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _percentile(values: list[float], q: float) -> float | None:
    finite = sorted(float(v) for v in values if math.isfinite(float(v)))
    if not finite:
        return None
    if len(finite) == 1:
        return round(finite[0], 3)
    position = (len(finite) - 1) * (q / 100.0)
    lo = int(math.floor(position)); hi = int(math.ceil(position))
    if lo == hi:
        return round(finite[lo], 3)
    weight = position - lo
    return round(finite[lo] * (1.0 - weight) + finite[hi] * weight, 3)


def summarize_height_deltas(values: list[float], total_samples: int) -> dict[str, Any]:
    finite = [float(v) for v in values if math.isfinite(float(v))]
    plausible = [v for v in finite if PLAUSIBLE_MIN_M <= v <= PLAUSIBLE_MAX_M]
    valid_count = len(finite)
    plausible_count = len(plausible)
    plausible_fraction = float(plausible_count / valid_count) if valid_count else 0.0
    valid_ratio = float(valid_count / total_samples) if total_samples > 0 else 0.0
    confidence = "insufficient"
    if plausible_count >= MIN_VALID_PIXELS and plausible_fraction >= MIN_PLAUSIBLE_FRACTION:
        confidence = "high" if plausible_count >= HIGH_VALID_PIXELS and plausible_fraction >= HIGH_PLAUSIBLE_FRACTION else "medium"

    p50 = _percentile(plausible, 50); p75 = _percentile(plausible, 75); p90 = _percentile(plausible, 90)
    candidate = p75 if confidence == "high" else p50 if confidence == "medium" else None
    policy = "high_confidence_p75" if confidence == "high" else "medium_confidence_p50" if confidence == "medium" else "no_candidate"
    flags: list[str] = []
    if candidate is not None and candidate < MIN_CANDIDATE_HEIGHT_M:
        flags.append("candidate_below_minimum_building_height")
        candidate = None; policy = "no_candidate"
    if p50 is not None and p90 is not None and p90 - p50 > LARGE_SPREAD_M:
        flags.append("large_p50_p90_spread_requires_secondary_review")
    negative_count = sum(1 for v in finite if v < PLAUSIBLE_MIN_M)
    over_count = sum(1 for v in finite if v > PLAUSIBLE_MAX_M)
    if valid_count and negative_count / valid_count > 0.10:
        flags.append("negative_sample_fraction_high")
    if valid_count and over_count / valid_count > 0.02:
        flags.append("extreme_positive_sample_fraction_high")

    return {
        "pixel_count_total": int(total_samples),
        "pixel_count_valid": valid_count,
        "valid_ratio": valid_ratio,
        "pixel_count_plausible": plausible_count,
        "plausible_fraction_of_valid": plausible_fraction,
        "negative_below_noise_count": negative_count,
        "over_250m_count": over_count,
        "raw_difference_m": {"p50": _percentile(finite, 50), "p75": _percentile(finite, 75), "p90": _percentile(finite, 90)},
        "plausible_difference_m": {"p50": p50, "p75": p75, "p90": p90},
        "confidence": confidence,
        "candidate_height_m": candidate,
        "candidate_policy": policy,
        "review_flags": sorted(flags),
        "runtime_approved": False,
        "secondary_validation_required": candidate is not None,
    }


def _find_tiff(extract_root: Path, kind: str, tile: str, filename: str) -> Path:
    matches = sorted((extract_root / kind / tile).rglob(filename))
    if len(matches) != 1:
        raise ValueError(f"{kind}/{tile}: expected one extracted TIFF named {filename}, found {matches}")
    return matches[0]


def sample_building(feature: dict[str, Any], raster_validation: dict[str, Any], extract_root: Path) -> tuple[list[float], int]:
    try:
        import numpy as np  # type: ignore
        import rasterio  # type: ignore
        from rasterio.features import geometry_mask, geometry_window  # type: ignore
        from rasterio.errors import WindowError  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy and rasterio are required for per-building height sampling") from exc

    geometry = feature.get("geometry")
    if not isinstance(geometry, dict) or geometry.get("type") not in ("Polygon", "MultiPolygon"):
        return [], 0
    dsm_rows = {row["tile"]: row for row in (raster_validation.get("dsm") or {}).get("rasters", [])}
    dtm_rows = {row["tile"]: row for row in (raster_validation.get("dtm") or {}).get("rasters", [])}
    if set(dsm_rows) != set(dtm_rows) or not dsm_rows:
        raise ValueError("DSM/DTM raster tile sets missing or different")

    deltas: list[float] = []
    total_samples = 0
    for tile in sorted(dsm_rows):
        dsm_meta = dsm_rows[tile]["raster"]; dtm_meta = dtm_rows[tile]["raster"]
        dsm_path = _find_tiff(extract_root, "dsm", tile, str(dsm_meta["filename"]))
        dtm_path = _find_tiff(extract_root, "dtm", tile, str(dtm_meta["filename"]))
        with rasterio.open(dsm_path) as dsm_src, rasterio.open(dtm_path) as dtm_src:
            if dsm_src.transform != dtm_src.transform or dsm_src.width != dtm_src.width or dsm_src.height != dtm_src.height:
                raise ValueError(f"{tile}: DSM/DTM alignment changed after validation")
            try:
                window = geometry_window(dsm_src, [geometry], pad_x=0, pad_y=0)
            except WindowError:
                continue
            if window.width <= 0 or window.height <= 0:
                continue
            dsm_arr = dsm_src.read(1, window=window, masked=True).astype("float64")
            dtm_arr = dtm_src.read(1, window=window, masked=True).astype("float64")
            if dsm_arr.shape != dtm_arr.shape:
                raise ValueError(f"{tile}: paired building windows differ")
            transform = rasterio.windows.transform(window, dsm_src.transform)
            inside = geometry_mask([geometry], out_shape=dsm_arr.shape, transform=transform, invert=True, all_touched=False)
            total_samples += int(np.count_nonzero(inside))
            dsm_plain = np.asarray(dsm_arr.filled(np.nan), dtype="float64")
            dtm_plain = np.asarray(dtm_arr.filled(np.nan), dtype="float64")
            valid = inside & (~np.ma.getmaskarray(dsm_arr)) & (~np.ma.getmaskarray(dtm_arr)) & np.isfinite(dsm_plain) & np.isfinite(dtm_plain)
            if np.any(valid):
                deltas.extend(float(v) for v in (dsm_plain[valid] - dtm_plain[valid]).tolist())
    return deltas, total_samples


def _stable_building_id(feature: dict[str, Any]) -> str:
    props = feature.get("properties") or {}
    value = props.get("INSPIRE_ID") or feature.get("id")
    if value not in (None, ""):
        return str(value)
    return "anon-" + _digest({"geometry": feature.get("geometry"), "properties": props})[:20]


def build(cell_dir: Path, value_evidence_path: Path, frontier_path: Path, raster_validation_path: Path, extract_root: Path) -> dict[str, Any]:
    source = _read(cell_dir / "manifest.json")
    value_evidence = _read(value_evidence_path)
    frontier = _read(frontier_path)
    raster_validation = _read(raster_validation_path)
    if source.get("format") != SOURCE_FORMAT or source.get("crs") != CRS:
        raise ValueError("unsupported authoritative source cell")
    if value_evidence.get("format") != VALUE_FORMAT or value_evidence.get("crs") != CRS:
        raise ValueError("unsupported elevation value evidence")
    if frontier.get("format") != FRONTIER_FORMAT or frontier.get("crs") != CRS:
        raise ValueError("unsupported elevation candidate frontier")
    if raster_validation.get("format") != RASTER_FORMAT or raster_validation.get("crs") != CRS:
        raise ValueError("unsupported elevation raster validation")
    cell_id = source.get("cell_id")
    if not isinstance(cell_id, str) or any(payload.get("cell_id") != cell_id for payload in (value_evidence, frontier, raster_validation)):
        raise ValueError("building-height evidence cell identity mismatch")
    if value_evidence.get("height_source_pair_ready") is not True or (frontier.get("heights") or {}).get("source_pair_ready") is not True:
        raise ValueError("height source pair is not ready for per-building sampling")
    if frontier.get("runtime_promotion_allowed") is not False:
        raise ValueError("elevation frontier must explicitly forbid runtime promotion")

    collection = _read(cell_dir / "raw" / "buildings.geojson")
    if collection.get("type") != "FeatureCollection":
        raise ValueError("authoritative buildings source is not a FeatureCollection")
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for feature in collection.get("features") or []:
        if not isinstance(feature, dict):
            continue
        building_id = _stable_building_id(feature)
        if building_id in seen:
            raise ValueError(f"duplicate authoritative building id inside cell: {building_id}")
        seen.add(building_id)
        deltas, total_samples = sample_building(feature, raster_validation, extract_root)
        stats = summarize_height_deltas(deltas, total_samples)
        props = feature.get("properties") or {}
        rows.append({
            "building_id": building_id,
            "source_feature_id": feature.get("id"),
            "area_m2_urbis": props.get("AREA"),
            "height_stats": stats,
            "candidate_height_m": stats["candidate_height_m"],
            "confidence": stats["confidence"],
            "runtime_approved": False,
            "secondary_validation_required": stats["candidate_height_m"] is not None,
        })
    rows.sort(key=lambda row: row["building_id"])
    counts = {name: sum(1 for row in rows if row["confidence"] == name) for name in ("high", "medium", "insufficient")}
    candidate_count = sum(1 for row in rows if row["candidate_height_m"] is not None)
    target = int((frontier.get("heights") or {}).get("building_sample_target_count", len(rows)))
    blockers: list[str] = []
    if target != len(rows):
        blockers.append("frontier_building_target_count_mismatch")
    if not rows:
        blockers.append("no_authoritative_buildings_to_sample")
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": source.get("bbox"),
        "method": "paired_DSM_minus_DTM_pixel_centers_inside_authoritative_UrbIS_building_footprints",
        "confidence_policy": {
            "minimum_plausible_pixels": MIN_VALID_PIXELS,
            "minimum_plausible_fraction": MIN_PLAUSIBLE_FRACTION,
            "high_minimum_plausible_pixels": HIGH_VALID_PIXELS,
            "high_minimum_plausible_fraction": HIGH_PLAUSIBLE_FRACTION,
            "high_candidate": "p75",
            "medium_candidate": "p50",
            "insufficient_candidate": None,
            "plausible_window_m": [PLAUSIBLE_MIN_M, PLAUSIBLE_MAX_M],
        },
        "source_value_evidence_digest": value_evidence.get("evidence_digest"),
        "source_raster_validation_digest": raster_validation.get("validation_digest"),
        "source_frontier_digest": frontier.get("frontier_digest"),
        "building_count": len(rows),
        "candidate_count": candidate_count,
        "runtime_approved_count": 0,
        "confidence_counts": counts,
        "blockers": blockers,
        "status": "height_candidates_derived_pending_secondary_validation" if candidate_count else "no_height_candidates_derived",
        "buildings": rows,
        "runtime_promotion_allowed": False,
        "maturity_effect": {
            "heights_gate": False,
            "reason": "per_building_candidates_require_independent_secondary_validation_before_runtime_use",
        },
    }
    result["candidate_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--value-evidence", type=Path, required=True)
    parser.add_argument("--frontier", type=Path, required=True)
    parser.add_argument("--raster-validation", type=Path, required=True)
    parser.add_argument("--extract-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.cell_dir, args.value_evidence, args.frontier, args.raster_validation, args.extract_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_BUILDING_HEIGHT_CANDIDATES_OK", result["cell_id"], result["building_count"], result["candidate_count"], result["confidence_counts"], result["candidate_digest"])


if __name__ == "__main__":
    main()
