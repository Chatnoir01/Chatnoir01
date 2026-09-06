#!/usr/bin/env python3
"""Fail-closed bilateral CIV-1 foot-landmark promotion gate.

Consumes independently rendered LeftFoot and RightFoot landmark receipts. Bilateral
landmark identity may become ready only when both receipts preserve Skeleton/Skin-
tied identity at the same samples/distances and satisfy the frozen raster rails.
This tool never promotes foot-slide, planted contact, animation, runtime,
player-view, or visual approval; those require separate contact-phase evidence.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

SAMPLES = [114, 115, 116, 117, 118]
DISTANCES = [2, 4, 8]
MAX_CENTROID_ERROR_PX = 1.5
MAX_PATH_RELATIVE_ERROR = 0.25


def _load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"receipt must be object: {path}")
    return data


def _validate_side(data: dict, side: str) -> dict:
    lower = side.lower()
    expected_schema = f"grand-bruxelles-civ1-{lower}-landmark-raster-analysis-v1"
    expected_semantic = f"magenta_raster_of_verified_{lower}_bone_pose"
    identity_key = f"single_{lower}_identity_preserved_2_4_8m"
    problems: list[str] = []

    if data.get("schema") != expected_schema:
        problems.append("schema")
    if data.get("diagnostic_only") is not True:
        problems.append("diagnostic_only")
    if data.get("landmark_semantic") != expected_semantic:
        problems.append("landmark_semantic")
    if data.get("samples") != SAMPLES:
        problems.append("samples")
    if data.get("distances_m") != DISTANCES:
        problems.append("distances")
    if float(data.get("max_centroid_error_px", 999.0)) != MAX_CENTROID_ERROR_PX:
        problems.append("centroid_rail")
    if float(data.get("max_path_relative_error", 999.0)) != MAX_PATH_RELATIVE_ERROR:
        problems.append("path_rail")
    if data.get(identity_key) is not True:
        problems.append("identity")
    if data.get("quantitative_landmark_candidate") is not True:
        problems.append("landmark_candidate")

    for flag in (
        "perceptual_2_8m_claimed",
        "planted_contact_claimed",
        "animation_correction_authorized",
        "runtime_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
    ):
        if data.get(flag) is not False:
            problems.append(flag)

    measurements = data.get("measurements")
    if not isinstance(measurements, list) or [m.get("distance_m") for m in measurements] != DISTANCES:
        problems.append("measurement_matrix")
        measurements = []

    max_centroid = 0.0
    max_path = 0.0
    for measurement in measurements:
        if measurement.get("passed") is not True:
            problems.append(f"distance_{measurement.get('distance_m')}_passed")
        if measurement.get("direction_match") is not True:
            problems.append(f"distance_{measurement.get('distance_m')}_direction")
        centroid = float(measurement.get("max_centroid_error_px", 999.0))
        path_error = float(measurement.get("path_relative_error", 999.0))
        max_centroid = max(max_centroid, centroid)
        max_path = max(max_path, path_error)
        if centroid > MAX_CENTROID_ERROR_PX:
            problems.append(f"distance_{measurement.get('distance_m')}_centroid")
        if path_error > MAX_PATH_RELATIVE_ERROR:
            problems.append(f"distance_{measurement.get('distance_m')}_path")
        records = measurement.get("records")
        if not isinstance(records, list) or [r.get("sample_index") for r in records] != SAMPLES:
            problems.append(f"distance_{measurement.get('distance_m')}_samples")

    return {
        "side": side,
        "ready": not problems,
        "problems": problems,
        "max_observed_centroid_error_px": max_centroid,
        "max_observed_path_relative_error": max_path,
    }


def analyze(left_path: Path, right_path: Path) -> dict:
    left = _validate_side(_load(left_path), "leftfoot")
    right = _validate_side(_load(right_path), "rightfoot")
    bilateral_ready = left["ready"] and right["ready"]
    blockers = []
    if not left["ready"]:
        blockers.append({"side": "LeftFoot", "problems": left["problems"]})
    if not right["ready"]:
        blockers.append({"side": "RightFoot", "problems": right["problems"]})

    return {
        "schema": "grand-bruxelles-civ1-bilateral-landmark-promotion-v1",
        "diagnostic_only": True,
        "source_semantic": "independent_skeleton_skin_tied_left_and_right_foot_raster_receipts",
        "samples": SAMPLES,
        "distances_m": DISTANCES,
        "max_centroid_error_px": MAX_CENTROID_ERROR_PX,
        "max_path_relative_error": MAX_PATH_RELATIVE_ERROR,
        "leftfoot": left,
        "rightfoot": right,
        "bilateral_identity_ready": bilateral_ready,
        "blockers": blockers,
        "bilateral_contact_phase_ready": False,
        "quantitative_foot_slide_candidate": False,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": (
            "AMELIORER_BILATERAL_LANDMARK_IDENTITY_READY_CONTACT_PHASE_REQUIRED_NO_PROMOTION"
            if bilateral_ready
            else "AMELIORER_BILATERAL_LANDMARK_IDENTITY_INCOMPLETE_NO_PROMOTION"
        ),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: analyze_civ1_bilateral_landmark_promotion.py LEFT.json RIGHT.json OUT.json", file=sys.stderr)
        return 2
    try:
        report = analyze(Path(argv[1]), Path(argv[2]))
        Path(argv[3]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_BILATERAL_LANDMARK_PROMOTION_FAIL: {exc}", file=sys.stderr)
        return 3
    print(
        "CIV1_BILATERAL_LANDMARK_PROMOTION_OK "
        f"left={report['leftfoot']['ready']} right={report['rightfoot']['ready']} "
        f"bilateral={report['bilateral_identity_ready']} contact={report['bilateral_contact_phase_ready']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
