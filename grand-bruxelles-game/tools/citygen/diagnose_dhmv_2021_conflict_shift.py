#!/usr/bin/env python3
"""Read-only temporal surface comparison for true CityGen height conflicts.

Compares official Brussels DSM-DTM 2021 against historical Digitaal Vlaanderen
DHMV II 2013-2015 on the exact same authoritative 2D building footprints.
The diagnostic describes surface-height distribution shifts only. It never
infers a physical building change, selects a winning source, or grants runtime
approval.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-citygen-dhmv-2021-conflict-shift-v1"
VALIDATION_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
CRS = "EPSG:31370"
CURRENT_PIXEL_M = 0.5
HISTORICAL_PIXEL_M = 1.0
EDGE_WIDTH_M = 1.0

_HERE = Path(__file__).resolve().parent
_AUTOPSY_PATH = _HERE / "diagnose_dsm_conflict_pixels.py"
_POLICY_PATH = _HERE / "build_semantic_dsm_height_comparison.py"


def _load(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load policy module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _finite(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _validate_pair(dsm_path: Path, dtm_path: Path, expected_pixel_m: float, label: str) -> None:
    try:
        import rasterio  # type: ignore
    except ImportError as exc:
        raise RuntimeError("rasterio is required for temporal conflict diagnostics") from exc
    with rasterio.open(dsm_path) as dsm, rasterio.open(dtm_path) as dtm:
        for src in (dsm, dtm):
            if src.crs is None or src.crs.to_epsg() != 31370:
                raise ValueError(f"{label} raster must remain EPSG:31370")
            if not math.isclose(abs(float(src.res[0])), expected_pixel_m, abs_tol=1e-6):
                raise ValueError(f"{label} x resolution changed: {src.res}")
            if not math.isclose(abs(float(src.res[1])), expected_pixel_m, abs_tol=1e-6):
                raise ValueError(f"{label} y resolution changed: {src.res}")
        if dsm.transform != dtm.transform or dsm.width != dtm.width or dsm.height != dtm.height:
            raise ValueError(f"{label} DSM/DTM alignment mismatch")


def compare_epoch_grids(
    current_inside: Any,
    current_deltas: Any,
    historical_inside: Any,
    historical_deltas: Any,
    *,
    primary_height_m: float,
    semantic_height_m: float,
    strong_delta_m: float,
    current_pixel_m: float = CURRENT_PIXEL_M,
    historical_pixel_m: float = HISTORICAL_PIXEL_M,
) -> dict[str, Any]:
    """Compare two independently sampled epochs with equal physical edge width."""
    autopsy = _load(_AUTOPSY_PATH, "citygen_dsm_conflict_autopsy_for_temporal_shift")
    if not math.isclose(float(strong_delta_m), 2.0, abs_tol=1e-12):
        raise ValueError(f"existing strong height threshold changed unexpectedly: {strong_delta_m}")
    if current_pixel_m <= 0 or historical_pixel_m <= 0:
        raise ValueError("pixel sizes must be positive")
    current_erosion = max(1, int(round(EDGE_WIDTH_M / current_pixel_m)))
    historical_erosion = max(1, int(round(EDGE_WIDTH_M / historical_pixel_m)))
    current = autopsy.analyze_grid(
        current_inside,
        current_deltas,
        primary_height_m=primary_height_m,
        semantic_height_m=semantic_height_m,
        strong_delta_m=strong_delta_m,
        erosion_pixels=current_erosion,
    )
    historical = autopsy.analyze_grid(
        historical_inside,
        historical_deltas,
        primary_height_m=primary_height_m,
        semantic_height_m=semantic_height_m,
        strong_delta_m=strong_delta_m,
        erosion_pixels=historical_erosion,
    )
    current_p50 = _finite(current["distribution_m"].get("p50"))
    historical_p50 = _finite(historical["distribution_m"].get("p50"))
    return {
        "edge_zone_nominal_width_m": EDGE_WIDTH_M,
        "current_2021": {
            "pixel_size_m": current_pixel_m,
            "edge_erosion_pixels": current_erosion,
            "grid": current,
        },
        "historical_2013_2015": {
            "pixel_size_m": historical_pixel_m,
            "edge_erosion_pixels": historical_erosion,
            "grid": historical,
        },
        "differences": {
            "p50_shift_2021_minus_historical_m": (
                round(current_p50 - historical_p50, 6)
                if current_p50 is not None and historical_p50 is not None
                else None
            ),
            "primary_band_fraction_shift": round(
                float(current["bands"]["primary"]["fraction_of_valid"])
                - float(historical["bands"]["primary"]["fraction_of_valid"]),
                9,
            ),
            "semantic_band_fraction_shift": round(
                float(current["bands"]["semantic"]["fraction_of_valid"])
                - float(historical["bands"]["semantic"]["fraction_of_valid"]),
                9,
            ),
            "interior_primary_band_fraction_shift": round(
                float(current["zones"]["interior"]["primary_band_fraction"])
                - float(historical["zones"]["interior"]["primary_band_fraction"]),
                9,
            ),
            "interior_semantic_band_fraction_shift": round(
                float(current["zones"]["interior"]["semantic_band_fraction"])
                - float(historical["zones"]["interior"]["semantic_band_fraction"]),
                9,
            ),
        },
        "policy": {
            "read_only": True,
            "surface_distribution_comparison_only": True,
            "physical_change_inference_allowed": False,
            "source_winner_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
            "thresholds_changed": False,
        },
    }


def build_report(
    buildings: dict[str, Any],
    validation: dict[str, Any],
    current_dsm: Path,
    current_dtm: Path,
    historical_dsm: Path,
    historical_dtm: Path,
) -> dict[str, Any]:
    if validation.get("format") != VALIDATION_FORMAT or validation.get("crs") != CRS:
        raise ValueError("unsupported secondary-height validation evidence")
    if validation.get("runtime_promotion_allowed") is not False:
        raise ValueError("secondary-height validation must forbid runtime promotion")
    if int(validation.get("runtime_approved_count", -1)) != 0:
        raise ValueError("secondary-height validation unexpectedly has runtime-approved candidates")

    _validate_pair(current_dsm, current_dtm, CURRENT_PIXEL_M, "current 2021")
    _validate_pair(historical_dsm, historical_dtm, HISTORICAL_PIXEL_M, "historical DHMV II")

    autopsy = _load(_AUTOPSY_PATH, "citygen_dsm_conflict_autopsy_for_temporal_report")
    policy = _load(_POLICY_PATH, "citygen_semantic_height_policy_for_temporal_report")
    strong_delta_m = float(policy.STRONG_DELTA_M)
    if not math.isclose(strong_delta_m, 2.0, abs_tol=1e-12):
        raise ValueError(f"existing strong height threshold changed unexpectedly: {strong_delta_m}")

    features = autopsy._feature_map(buildings)
    candidates = validation.get("candidates")
    if not isinstance(candidates, list):
        raise ValueError("validation candidates must be a list")
    conflicts = [r for r in candidates if isinstance(r, dict) and r.get("secondary_status") == "blocked_conflict"]
    if not conflicts:
        raise ValueError("no blocked height conflicts found")
    if any(r.get("runtime_approved") is not False for r in conflicts):
        raise ValueError("blocked conflict unexpectedly runtime-approved")

    records: list[dict[str, Any]] = []
    for row in sorted(conflicts, key=lambda x: str(x.get("building_id") or "")):
        building_id = str(row.get("building_id") or "")
        primary = _finite(row.get("candidate_height_m"))
        semantic = _finite(row.get("semantic_height_m"))
        feature = features.get(building_id)
        if not building_id or primary is None or semantic is None or feature is None:
            raise ValueError(f"blocked conflict lacks complete evidence: {building_id}")
        cur_inside, cur_deltas, cur_pixel = autopsy._sample_conflict(feature, current_dsm, current_dtm)
        hist_inside, hist_deltas, hist_pixel = autopsy._sample_conflict(feature, historical_dsm, historical_dtm)
        comparison = compare_epoch_grids(
            cur_inside,
            cur_deltas,
            hist_inside,
            hist_deltas,
            primary_height_m=primary,
            semantic_height_m=semantic,
            strong_delta_m=strong_delta_m,
            current_pixel_m=cur_pixel,
            historical_pixel_m=hist_pixel,
        )
        if comparison["current_2021"]["grid"]["valid_pixel_count"] <= 0:
            raise ValueError(f"current conflict has no valid pixels: {building_id}")
        if comparison["historical_2013_2015"]["grid"]["valid_pixel_count"] <= 0:
            raise ValueError(f"historical conflict has no valid pixels: {building_id}")
        records.append({
            "building_id": building_id,
            "primary_height_m": primary,
            "semantic_height_m": semantic,
            "secondary_abs_delta_m": _finite(row.get("abs_delta_m")),
            "comparison": comparison,
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
        })

    return {
        "schema": SCHEMA,
        "cell_id": str(validation.get("cell_id") or ""),
        "crs": CRS,
        "counts": {
            "blocked_conflicts": len(records),
            "current_2021_sampled": len(records),
            "historical_2013_2015_sampled": len(records),
        },
        "policy": {
            "read_only": True,
            "surface_distribution_comparison_only": True,
            "physical_change_inference_allowed": False,
            "source_winner_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_promotion_allowed": False,
            "runtime_approval": False,
            "thresholds_changed": False,
            "comparison_strong_delta_m": strong_delta_m,
            "edge_zone_nominal_width_m": EDGE_WIDTH_M,
            "current_source_note": "official Brussels LiDAR DSM-DTM 2021",
            "historical_source_note": "Digitaal Vlaanderen DHMV II 2013-2015; diagnostic context only",
        },
        "records": records,
        "runtime_promotion_allowed": False,
        "runtime_approved_count": 0,
        "next_action": "inspect_current_authoritative_structure_evidence_for_each_conflict_before_any_resolution",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--current-dsm", type=Path, required=True)
    parser.add_argument("--current-dtm", type=Path, required=True)
    parser.add_argument("--historical-dsm", type=Path, required=True)
    parser.add_argument("--historical-dtm", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = build_report(
        _read(args.buildings),
        _read(args.validation),
        args.current_dsm,
        args.current_dtm,
        args.historical_dsm,
        args.historical_dtm,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "DHMV_2021_CONFLICT_SHIFT_OK",
        report["cell_id"],
        f"conflicts={report['counts']['blocked_conflicts']}",
        "automatic_resolution=false",
        "runtime_promotion=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
