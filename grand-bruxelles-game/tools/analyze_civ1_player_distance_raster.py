#!/usr/bin/env python3
"""Measure CIV-1 foot-region motion in real 2/4/8 m Godot rasters.

Diagnostic-only. The validated single-bottom-row primitive remains the primary
measurement. A bounded four-row estimator is recorded independently as an A/B
fallback for distant rasters where the primary row is below its sampling floor.
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
        agreement_ratio = None
        if primary_resolved and multirow_resolved:
            denom = max(primary_path, multirow_path, 1e-9)
            agreement_ratio = abs(primary_path - multirow_path) / denom

        distances.append({
            "distance_m": distance,
            "primary": {
                "semantic": "validated_single_bottom_row",
                "measurement_resolved": primary_resolved,
                "measurement_error": primary_error,
                "bottom_centroid_path_px": primary_path,
                "min_bottom_pixel_count": min((r["bottom_pixel_count"] for r in primary_records), default=None),
                "records": primary_records,
            },
            "multirow": {
                "semantic": "bounded_four_bottom_rows_ab_estimator",
                "measurement_resolved": multirow_resolved,
                "measurement_error": multirow_error,
                "centroid_path_px": multirow_path,
                "min_region_pixel_count": min((r["pixel_count"] for r in multirow_records), default=None),
                "records": multirow_records,
            },
            "ab_path_relative_difference": agreement_ratio,
            "ab_agreement_claimed": False,
        })

    primary_unresolved = [d["distance_m"] for d in distances if not d["primary"]["measurement_resolved"]]
    multirow_unresolved = [d["distance_m"] for d in distances if not d["multirow"]["measurement_resolved"]]
    recovered_by_multirow = [
        d["distance_m"] for d in distances
        if not d["primary"]["measurement_resolved"] and d["multirow"]["measurement_resolved"]
    ]
    return {
        "schema": "grand-bruxelles-civ1-player-distance-raster-analysis-v2",
        "diagnostic_only": True,
        "source_semantic": "actual_godot_1280x720_player_distance_rasters",
        "distances_m": list(DISTANCES),
        "samples": list(SAMPLES),
        "multirow_depth": MULTIROW_DEPTH,
        "distance_measurements": distances,
        "primary_unresolved_distances_m": primary_unresolved,
        "multirow_unresolved_distances_m": multirow_unresolved,
        "recovered_by_multirow_distances_m": recovered_by_multirow,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_MULTIROW_AB_EVIDENCE_RECORDED_NO_PROMOTION",
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
    print(f"CIV1_PLAYER_DISTANCE_ANALYSIS_OK primary={primary} multirow={multirow} recovered={report['recovered_by_multirow_distances_m']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
