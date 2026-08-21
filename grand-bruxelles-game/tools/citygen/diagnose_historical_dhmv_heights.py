#!/usr/bin/env python3
"""Read-only historical DHMV II third-height diagnostic for blocked CityGen candidates.

The historical Digitaal Vlaanderen DHMV II DSM/DTM pair is used only as an
additional observation. It never validates, resolves, or promotes a candidate.
Sampling reuses the production DSM-DTM summary policy and comparison reuses the
existing strong-delta threshold without weakening either contract.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
TRIAGE_SCHEMA = "grand-bruxelles-citygen-blocked-secondary-height-triage-v1"
PRIMARY_FORMAT = "grand-bruxelles-cell-building-height-candidates-v1"
SECONDARY_SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
OUTPUT_SCHEMA = "grand-bruxelles-citygen-historical-dhmv-third-height-diagnostic-v1"
CRS = "EPSG:31370"
ADJUDICATION_ROUTES = {
    "independent_height_adjudication_required",
    "primary_confidence_corroboration_required",
    "cross_source_height_adjudication_required",
    "dual_uncertainty_requires_new_evidence",
}


def _load_module(filename: str, name: str):
    path = HERE / filename
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load production policy module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_PRIMARY_POLICY = _load_module(
    "derive_cell_building_height_candidates.py", "citygen_primary_height_policy"
)
_SECONDARY_POLICY = _load_module(
    "build_semantic_dsm_height_comparison.py", "citygen_secondary_height_policy"
)
STRONG_DELTA_M = float(_SECONDARY_POLICY.STRONG_DELTA_M)


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def _validate_inputs(
    triage: dict[str, Any], primary: dict[str, Any], secondary: dict[str, Any]
) -> str:
    if triage.get("schema") != TRIAGE_SCHEMA or triage.get("crs") != CRS:
        raise ValueError("unsupported blocked secondary-height triage input")
    triage_policy = triage.get("policy") or {}
    if (
        triage_policy.get("read_only") is not True
        or triage_policy.get("thresholds_changed") is not False
        or triage_policy.get("runtime_approval") is not False
        or triage.get("runtime_promotion_allowed") is not False
    ):
        raise ValueError("blocked secondary-height triage is not fail-closed")

    if primary.get("format") != PRIMARY_FORMAT or primary.get("crs") != CRS:
        raise ValueError("unsupported primary building-height candidate input")
    if (
        primary.get("runtime_promotion_allowed") is not False
        or primary.get("runtime_approved_count") != 0
    ):
        raise ValueError("primary building-height candidates unexpectedly allow runtime use")

    if secondary.get("schema") != SECONDARY_SCHEMA or secondary.get("source_crs") != CRS:
        raise ValueError("unsupported secondary semantic-height input")
    if (
        secondary.get("runtime_approved") is not False
        or (secondary.get("policy") or {}).get("runtime_approval") is not False
    ):
        raise ValueError("secondary semantic-height evidence unexpectedly allows runtime use")

    cell_id = triage.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id:
        raise ValueError("triage cell id is missing")
    if primary.get("cell_id") != cell_id or secondary.get("cell") != cell_id:
        raise ValueError("historical DHMV diagnostic cell identity mismatch")
    return cell_id


def _index_primary(primary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = primary.get("buildings")
    if not isinstance(rows, list):
        raise ValueError("primary building rows are invalid")
    indexed: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid primary building row")
        building_id = str(row.get("building_id") or "")
        if not building_id or building_id in indexed:
            raise ValueError(f"invalid or duplicate primary building id: {building_id!r}")
        if row.get("runtime_approved") is not False:
            raise ValueError(f"primary row unexpectedly runtime-approved: {building_id}")
        indexed[building_id] = row
    return indexed


def _index_secondary(secondary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = secondary.get("records")
    if not isinstance(rows, list):
        raise ValueError("secondary semantic records are invalid")
    indexed: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid secondary semantic row")
        building_id = str(row.get("building_id") or "")
        if not building_id:
            continue
        if building_id in indexed:
            raise ValueError(f"duplicate secondary semantic building id: {building_id}")
        if row.get("runtime_approved") is not False:
            raise ValueError(f"secondary row unexpectedly runtime-approved: {building_id}")
        indexed[building_id] = row
    return indexed


def _relation(
    historical_height: float | None,
    primary_height: float | None,
    semantic_height: float | None,
) -> tuple[str, float | None, float | None]:
    if historical_height is None:
        return "historical_measurement_insufficient", None, None
    delta_primary = (
        abs(historical_height - primary_height) if primary_height is not None else None
    )
    delta_semantic = (
        abs(historical_height - semantic_height) if semantic_height is not None else None
    )
    primary_ok = delta_primary is not None and delta_primary <= STRONG_DELTA_M
    semantic_ok = delta_semantic is not None and delta_semantic <= STRONG_DELTA_M
    if primary_ok and semantic_ok:
        return "historical_corroborates_both", delta_primary, delta_semantic
    if primary_ok:
        return "historical_corroborates_primary_only", delta_primary, delta_semantic
    if semantic_ok:
        return "historical_corroborates_semantic_only", delta_primary, delta_semantic
    return "historical_conflicts_both", delta_primary, delta_semantic


def build_report(
    triage: dict[str, Any],
    primary: dict[str, Any],
    secondary: dict[str, Any],
    measurements: dict[str, dict[str, Any]],
    source: dict[str, Any],
) -> dict[str, Any]:
    cell_id = _validate_inputs(triage, primary, secondary)
    primary_by_id = _index_primary(primary)
    secondary_by_id = _index_secondary(secondary)

    blocked = triage.get("blocked_candidates")
    if not isinstance(blocked, list):
        raise ValueError("triage blocked candidate rows are invalid")

    records: list[dict[str, Any]] = []
    coverage_gap_excluded = 0
    seen: set[str] = set()
    for triage_row in blocked:
        if not isinstance(triage_row, dict):
            raise ValueError("invalid triage row")
        building_id = str(triage_row.get("building_id") or "")
        route = str(triage_row.get("triage_route") or "")
        if not building_id or building_id in seen:
            raise ValueError(f"invalid or duplicate triage building id: {building_id!r}")
        seen.add(building_id)
        if triage_row.get("runtime_approved") is not False or triage_row.get(
            "automatic_resolution_allowed"
        ) is not False:
            raise ValueError(f"triage row is not fail-closed: {building_id}")
        if route not in ADJUDICATION_ROUTES:
            if route == "secondary_coverage_gap":
                coverage_gap_excluded += 1
            continue

        primary_row = primary_by_id.get(building_id)
        secondary_row = secondary_by_id.get(building_id)
        if primary_row is None or secondary_row is None:
            raise ValueError(
                f"adjudication candidate lacks primary or semantic evidence: {building_id}"
            )
        primary_height = _finite(primary_row.get("candidate_height_m"))
        semantic_height = _finite(secondary_row.get("semantic_height_m"))
        if primary_height is None or semantic_height is None:
            raise ValueError(f"adjudication candidate has non-finite source height: {building_id}")

        measurement = measurements.get(building_id) or {}
        historical_height = _finite(measurement.get("candidate_height_m"))
        relation, delta_primary, delta_semantic = _relation(
            historical_height, primary_height, semantic_height
        )
        records.append(
            {
                "building_id": building_id,
                "triage_route": route,
                "primary_height_m": primary_height,
                "primary_confidence": str(primary_row.get("confidence") or ""),
                "semantic_height_m": semantic_height,
                "historical_height_m": historical_height,
                "historical_confidence": str(measurement.get("confidence") or "insufficient"),
                "historical_height_stats": measurement.get("height_stats") or {},
                "historical_relation": relation,
                "historical_delta_to_primary_m": delta_primary,
                "historical_delta_to_semantic_m": delta_semantic,
                "automatic_resolution_allowed": False,
                "runtime_approved": False,
            }
        )

    records.sort(key=lambda row: row["building_id"])
    relation_names = (
        "historical_corroborates_both",
        "historical_corroborates_primary_only",
        "historical_corroborates_semantic_only",
        "historical_conflicts_both",
        "historical_measurement_insufficient",
    )
    counts: dict[str, int] = {
        "adjudication_candidates": len(records),
        "coverage_gap_excluded": coverage_gap_excluded,
    }
    for name in relation_names:
        counts[name] = sum(row["historical_relation"] == name for row in records)
    counts["historical_measurement_available"] = sum(
        row["historical_height_m"] is not None for row in records
    )

    result: dict[str, Any] = {
        "schema": OUTPUT_SCHEMA,
        "cell_id": cell_id,
        "crs": CRS,
        "source": source,
        "source_triage_digest": triage.get("triage_digest") or _digest(triage),
        "source_primary_digest": primary.get("candidate_digest") or _digest(primary),
        "source_secondary_digest": _digest(secondary),
        "policy": {
            "read_only": True,
            "historical_evidence_is_runtime_authority": False,
            "automatic_resolution": False,
            "thresholds_changed": False,
            "comparison_strong_delta_m": STRONG_DELTA_M,
            "historical_sampling_policy": "same summarize_height_deltas policy as autonomous DSM-DTM candidate derivation",
            "temporal_note": "DHMV II is a 2013-2015 historical observation and cannot by itself validate a 2026 building state",
        },
        "counts": counts,
        "records": records,
        "runtime_promotion_allowed": False,
        "runtime_approved_count": 0,
        "next_action": "use_historical_result_as_diagnostic_context_only_and_collect_current_authoritative_adjudication_evidence",
    }
    result["diagnostic_digest"] = _digest(result)
    return result


def _load_adjudication_ids(triage: dict[str, Any]) -> set[str]:
    rows = triage.get("blocked_candidates")
    if not isinstance(rows, list):
        raise ValueError("triage blocked candidate rows are invalid")
    ids: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid triage row")
        route = str(row.get("triage_route") or "")
        if route not in ADJUDICATION_ROUTES:
            continue
        building_id = str(row.get("building_id") or "")
        if not building_id or building_id in ids:
            raise ValueError(f"invalid or duplicate adjudication id: {building_id!r}")
        ids.add(building_id)
    return ids


def measure_historical_heights(
    buildings: dict[str, Any],
    adjudication_ids: set[str],
    dsm_path: Path,
    dtm_path: Path,
) -> dict[str, dict[str, Any]]:
    try:
        import numpy as np  # type: ignore
        import rasterio  # type: ignore
        from rasterio.errors import WindowError  # type: ignore
        from rasterio.features import geometry_mask, geometry_window  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy and rasterio are required for DHMV height diagnostics") from exc

    if buildings.get("type") != "FeatureCollection":
        raise ValueError("authoritative buildings source is not a FeatureCollection")
    features = buildings.get("features")
    if not isinstance(features, list):
        raise ValueError("authoritative buildings feature list is invalid")

    measurements: dict[str, dict[str, Any]] = {}
    found: set[str] = set()
    with rasterio.open(dsm_path) as dsm_src, rasterio.open(dtm_path) as dtm_src:
        if dsm_src.crs is None or dtm_src.crs is None:
            raise ValueError("historical DHMV rasters lack CRS")
        if dsm_src.crs.to_epsg() != 31370 or dtm_src.crs.to_epsg() != 31370:
            raise ValueError("historical DHMV rasters must remain EPSG:31370")
        if (
            dsm_src.transform != dtm_src.transform
            or dsm_src.width != dtm_src.width
            or dsm_src.height != dtm_src.height
        ):
            raise ValueError("historical DHMV DSM/DTM rasters are not aligned")

        for feature in features:
            if not isinstance(feature, dict):
                continue
            building_id = str(_PRIMARY_POLICY._stable_building_id(feature))
            if building_id not in adjudication_ids:
                continue
            if building_id in found:
                raise ValueError(f"duplicate authoritative building id: {building_id}")
            found.add(building_id)
            geometry = feature.get("geometry")
            if not isinstance(geometry, dict) or geometry.get("type") not in (
                "Polygon",
                "MultiPolygon",
            ):
                measurements[building_id] = {
                    "candidate_height_m": None,
                    "confidence": "insufficient",
                    "height_stats": _PRIMARY_POLICY.summarize_height_deltas([], 0),
                }
                continue
            try:
                window = geometry_window(dsm_src, [geometry], pad_x=0, pad_y=0)
            except WindowError:
                measurements[building_id] = {
                    "candidate_height_m": None,
                    "confidence": "insufficient",
                    "height_stats": _PRIMARY_POLICY.summarize_height_deltas([], 0),
                }
                continue
            if window.width <= 0 or window.height <= 0:
                measurements[building_id] = {
                    "candidate_height_m": None,
                    "confidence": "insufficient",
                    "height_stats": _PRIMARY_POLICY.summarize_height_deltas([], 0),
                }
                continue

            dsm_arr = dsm_src.read(1, window=window, masked=True).astype("float64")
            dtm_arr = dtm_src.read(1, window=window, masked=True).astype("float64")
            if dsm_arr.shape != dtm_arr.shape:
                raise ValueError(f"historical paired building windows differ: {building_id}")
            transform = rasterio.windows.transform(window, dsm_src.transform)
            inside = geometry_mask(
                [geometry],
                out_shape=dsm_arr.shape,
                transform=transform,
                invert=True,
                all_touched=False,
            )
            total_samples = int(np.count_nonzero(inside))
            dsm_plain = np.asarray(dsm_arr.filled(np.nan), dtype="float64")
            dtm_plain = np.asarray(dtm_arr.filled(np.nan), dtype="float64")
            valid = (
                inside
                & (~np.ma.getmaskarray(dsm_arr))
                & (~np.ma.getmaskarray(dtm_arr))
                & np.isfinite(dsm_plain)
                & np.isfinite(dtm_plain)
            )
            deltas = (
                [float(v) for v in (dsm_plain[valid] - dtm_plain[valid]).tolist()]
                if np.any(valid)
                else []
            )
            stats = _PRIMARY_POLICY.summarize_height_deltas(deltas, total_samples)
            measurements[building_id] = {
                "candidate_height_m": stats.get("candidate_height_m"),
                "confidence": str(stats.get("confidence") or "insufficient"),
                "height_stats": stats,
            }

    for building_id in sorted(adjudication_ids - found):
        measurements[building_id] = {
            "candidate_height_m": None,
            "confidence": "insufficient",
            "height_stats": _PRIMARY_POLICY.summarize_height_deltas([], 0),
        }
    return measurements


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--triage", type=Path, required=True)
    parser.add_argument("--primary", type=Path, required=True)
    parser.add_argument("--secondary", type=Path, required=True)
    parser.add_argument("--dsm", type=Path, required=True)
    parser.add_argument("--dtm", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    triage = _read(args.triage)
    primary = _read(args.primary)
    secondary = _read(args.secondary)
    _validate_inputs(triage, primary, secondary)
    adjudication_ids = _load_adjudication_ids(triage)
    measurements = measure_historical_heights(
        _read(args.buildings), adjudication_ids, args.dsm, args.dtm
    )
    result = build_report(
        triage, primary, secondary, measurements, _read(args.source)
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "HISTORICAL_DHMV_HEIGHT_DIAGNOSTIC_OK",
        result["cell_id"],
        f"adjudication={result['counts']['adjudication_candidates']}",
        f"measured={result['counts']['historical_measurement_available']}",
        "automatic_resolution=false",
        "runtime_promotion=false",
    )


if __name__ == "__main__":
    main()
