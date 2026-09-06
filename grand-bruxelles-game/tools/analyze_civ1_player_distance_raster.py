#!/usr/bin/env python3
"""Measure CIV-1 foot-region motion in real 2/4/8 m Godot rasters.

Diagnostic-only. The validated single-bottom-row primitive remains the primary
measurement. A bounded four-row estimator is recorded independently as an A/B
fallback for distant rasters where the primary row is below its sampling floor.
The fallback must calibrate against primary-resolved nearer distances before any
recovered distant value is considered qualified diagnostic evidence.
Neither estimator may promote perceptual, planted-contact, runtime, player-view,
or animation-correction claims.
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

DISTANCES = (2, 4, 8)
SAMPLES = (115, 116, 117, 118)
MULTIROW_DEPTH = 4
MIN_PRIMARY_PIXELS = 20
MIN_MULTIROW_PIXELS = 40
MAX_AB_PATH_RELATIVE_DIFFERENCE = 0.25
MIN_DIRECTION_SIGNAL_PX = 0.25


def _load_sole_module():
    path = Path(__file__).with_name("analyze_civ1_rendered_sole_capture.py")
    spec = importlib.util.spec_from_file_location("civ1_rendered_sole", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load rendered-sole analyzer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _multirow_silhouette(sole, path: Path) -> dict:
    """Measure a bounded near-white region ending at the silhouette bottom row."""
    width, height, rows = sole.read_png(path)
    channels = len(rows[0]) // width
    white_by_row: list[tuple[int, list[int]]] = []
    for y, row in enumerate(rows):
        xs: list[int] = []
        for x in range(width):
            i = x * channels
            if row[i] >= 220 and row[i + 1] >= 220 and row[i + 2] >= 220:
                xs.append(x)
        if xs:
            white_by_row.append((y, xs))
    if not white_by_row:
        raise ValueError(f"no rendered silhouette pixels in {path}")
    bottom = white_by_row[-1][0]
    selected = [(y, xs) for y, xs in white_by_row if bottom - MULTIROW_DEPTH + 1 <= y <= bottom]
    points = [(x, y) for y, xs in selected for x in xs]
    if len(points) < MIN_MULTIROW_PIXELS:
        raise ValueError(f"insufficient multirow silhouette pixels in {path}: {len(points)}")
    return {
        "bottom_y_px": bottom,
        "row_depth": MULTIROW_DEPTH,
        "pixel_count": len(points),
        "centroid_x_px": sum(x for x, _ in points) / len(points),
        "centroid_y_px": sum(y for _, y in points) / len(points),
    }


def _path(records: list[dict], key: str) -> float:
    value = sum(abs(records[i][key] - records[i - 1][key]) for i in range(1, len(records)))
    if not math.isfinite(value):
        raise ValueError("non-finite raster path")
    return value


def _signed_displacement(records: list[dict], key: str) -> float:
    value = records[-1][key] - records[0][key]
    if not math.isfinite(value):
        raise ValueError("non-finite raster displacement")
    return value


def _direction_match(a: float, b: float) -> bool:
    if abs(a) < MIN_DIRECTION_SIGNAL_PX or abs(b) < MIN_DIRECTION_SIGNAL_PX:
        return False
    return (a > 0) == (b > 0)


def analyze(capture_dir: Path) -> dict:
    sole = _load_sole_module()
    distances = []
    for distance in DISTANCES:
        primary_records: list[dict] = []
        multirow_records: list[dict] = []
        primary_error = None
        multirow_error = None
        for sample in SAMPLES:
            path = capture_dir / f"civ1-distance-{distance}m-{sample}.png"
            if not path.is_file():
                raise ValueError(f"missing capture d={distance} sample={sample}")
            if primary_error is None:
                try:
                    primary_records.append({"sample_index": sample, **sole.bottom_silhouette(path)})
                except ValueError as exc:
                    primary_error = str(exc)
            try:
                multirow_records.append({"sample_index": sample, **_multirow_silhouette(sole, path)})
            except ValueError as exc:
                if multirow_error is None:
                    multirow_error = str(exc)

        primary_resolved = primary_error is None and len(primary_records) == len(SAMPLES)
        multirow_resolved = multirow_error is None and len(multirow_records) == len(SAMPLES)
        primary_path = _path(primary_records, "bottom_centroid_x_px") if primary_resolved else None
        multirow_path = _path(multirow_records, "centroid_x_px") if multirow_resolved else None
        primary_signed = _signed_displacement(primary_records, "bottom_centroid_x_px") if primary_resolved else None
        multirow_signed = _signed_displacement(multirow_records, "centroid_x_px") if multirow_resolved else None
        agreement_ratio = None
        direction_match = None
        path_within_tolerance = None
        if primary_resolved and multirow_resolved:
            denom = max(primary_path, multirow_path, 1e-9)
            agreement_ratio = abs(primary_path - multirow_path) / denom
            direction_match = _direction_match(primary_signed, multirow_signed)
            path_within_tolerance = agreement_ratio <= MAX_AB_PATH_RELATIVE_DIFFERENCE

        distances.append({
            "distance_m": distance,
            "primary": {
                "semantic": "validated_single_bottom_row",
                "measurement_resolved": primary_resolved,
                "measurement_error": primary_error,
                "bottom_centroid_path_px": primary_path,
                "signed_displacement_px": primary_signed,
                "min_bottom_pixel_count": min((r["bottom_pixel_count"] for r in primary_records), default=None),
                "records": primary_records,
            },
            "multirow": {
                "semantic": "bounded_four_bottom_rows_ab_estimator",
                "measurement_resolved": multirow_resolved,
                "measurement_error": multirow_error,
                "centroid_path_px": multirow_path,
                "signed_displacement_px": multirow_signed,
                "min_region_pixel_count": min((r["pixel_count"] for r in multirow_records), default=None),
                "records": multirow_records,
            },
            "ab_path_relative_difference": agreement_ratio,
            "ab_direction_match": direction_match,
            "ab_path_within_tolerance": path_within_tolerance,
            "ab_agreement_claimed": False,
        })

    primary_unresolved = [d["distance_m"] for d in distances if not d["primary"]["measurement_resolved"]]
    multirow_unresolved = [d["distance_m"] for d in distances if not d["multirow"]["measurement_resolved"]]
    raw_recovered = [
        d["distance_m"] for d in distances
        if not d["primary"]["measurement_resolved"] and d["multirow"]["measurement_resolved"]
    ]

    calibration_distances = [
        d for d in distances
        if d["distance_m"] < max(DISTANCES)
        and d["primary"]["measurement_resolved"]
        and d["multirow"]["measurement_resolved"]
    ]
    calibration_failures: list[dict] = []
    for d in calibration_distances:
        reasons = []
        if d["ab_direction_match"] is not True:
            reasons.append("signed_direction_mismatch_or_under_signal")
        if d["ab_path_within_tolerance"] is not True:
            reasons.append("path_relative_difference_exceeds_tolerance")
        if reasons:
            calibration_failures.append({"distance_m": d["distance_m"], "reasons": reasons})

    calibration_passed = len(calibration_distances) >= 2 and not calibration_failures
    qualified_recovered = raw_recovered if calibration_passed else []
    verdict = (
        "AMELIORER_MULTIROW_CALIBRATED_RECOVERY_AVAILABLE_NO_PROMOTION"
        if qualified_recovered
        else "AMELIORER_MULTIROW_FALLBACK_REJECTED_BY_CALIBRATION_NO_PROMOTION"
        if raw_recovered and not calibration_passed
        else "AMELIORER_MULTIROW_AB_EVIDENCE_RECORDED_NO_PROMOTION"
    )

    return {
        "schema": "grand-bruxelles-civ1-player-distance-raster-analysis-v3",
        "diagnostic_only": True,
        "source_semantic": "actual_godot_1280x720_player_distance_rasters",
        "distances_m": list(DISTANCES),
        "samples": list(SAMPLES),
        "multirow_depth": MULTIROW_DEPTH,
        "multirow_calibration": {
            "required_near_distances_m": [2, 4],
            "max_path_relative_difference": MAX_AB_PATH_RELATIVE_DIFFERENCE,
            "min_direction_signal_px": MIN_DIRECTION_SIGNAL_PX,
            "passed": calibration_passed,
            "failures": calibration_failures,
        },
        "distance_measurements": distances,
        "primary_unresolved_distances_m": primary_unresolved,
        "multirow_unresolved_distances_m": multirow_unresolved,
        "raw_recovered_by_multirow_distances_m": raw_recovered,
        "qualified_recovered_by_multirow_distances_m": qualified_recovered,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": verdict,
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_player_distance_raster.py CAPTURE_DIR OUT.json", file=sys.stderr)
        return 2
    try:
        report = analyze(Path(argv[1]))
        Path(argv[2]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_PLAYER_DISTANCE_ANALYSIS_FAIL: {exc}", file=sys.stderr)
        return 3
    primary = {d["distance_m"]: d["primary"]["bottom_centroid_path_px"] for d in report["distance_measurements"]}
    multirow = {d["distance_m"]: d["multirow"]["centroid_path_px"] for d in report["distance_measurements"]}
    print(
        "CIV1_PLAYER_DISTANCE_ANALYSIS_OK "
        f"primary={primary} multirow={multirow} "
        f"raw_recovered={report['raw_recovered_by_multirow_distances_m']} "
        f"qualified_recovered={report['qualified_recovered_by_multirow_distances_m']} "
        f"calibrated={report['multirow_calibration']['passed']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
