#!/usr/bin/env python3
"""Correlate CIV-1 rendered-raster sole motion with canonical-ground world motion.

Diagnostic-only. This combines two already fail-closed receipts; it does not infer
planted contact, perceptual visibility at 2-8 m, ART-PASS, player-view approval,
or authorization to modify locomotion.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

RASTER_SCHEMA = "grand-bruxelles-civ1-rendered-sole-silhouette-v1"
GROUND_SCHEMA = "grand-bruxelles-civ1-left-ground-reference-v3"
CANDIDATE = [115, 116, 117, 118]
FORBIDDEN_TRUE = (
    "ground_contact_claimed",
    "rendered_sole_contact_claimed",
    "runtime_authorized",
    "visual_approval_claimed",
    "player_view_claimed",
)


class CorrelationError(ValueError):
    pass


def _finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CorrelationError(f"{field}: expected number")
    value = float(value)
    if not math.isfinite(value):
        raise CorrelationError(f"{field}: non-finite")
    return value


def correlate(raster: dict[str, Any], ground: dict[str, Any]) -> dict[str, Any]:
    if raster.get("schema") != RASTER_SCHEMA:
        raise CorrelationError("raster schema")
    if ground.get("schema") != GROUND_SCHEMA:
        raise CorrelationError("ground schema")
    if raster.get("candidate_samples") != CANDIDATE:
        raise CorrelationError("raster candidate samples")
    if ground.get("target_left_candidate_samples") != CANDIDATE:
        raise CorrelationError("ground candidate samples")
    if raster.get("source_semantic") != "actual_godot_1280x720_low_side_raster":
        raise CorrelationError("raster source semantic")
    if ground.get("reference_semantic") != "canonical_main_ground_collision_raycast":
        raise CorrelationError("ground reference semantic")
    if ground.get("resolution") != [1280, 720]:
        raise CorrelationError("ground resolution")
    for receipt_name, receipt in (("raster", raster), ("ground", ground)):
        for flag in FORBIDDEN_TRUE:
            if receipt.get(flag) is not False:
                raise CorrelationError(f"{receipt_name} {flag}")

    world_path_m = _finite(ground.get("candidate_left_horizontal_path_m"), "candidate_left_horizontal_path_m")
    raster_path_px = _finite(raster.get("candidate_bottom_centroid_path_px"), "candidate_bottom_centroid_path_px")
    bottom_span_px = _finite(raster.get("candidate_bottom_row_span_px"), "candidate_bottom_row_span_px")
    min_clearance_m = _finite(ground.get("candidate_left_min_clearance_m"), "candidate_left_min_clearance_m")
    max_clearance_m = _finite(ground.get("candidate_left_max_clearance_m"), "candidate_left_max_clearance_m")
    for field, value in (
        ("world_path_m", world_path_m),
        ("raster_path_px", raster_path_px),
        ("bottom_span_px", bottom_span_px),
        ("min_clearance_m", min_clearance_m),
        ("max_clearance_m", max_clearance_m),
    ):
        if value < 0.0:
            raise CorrelationError(f"{field}: negative")
    if min_clearance_m > max_clearance_m:
        raise CorrelationError("clearance ordering")

    motion_in_both = world_path_m > 0.0 and raster_path_px > 0.0
    mm_per_px = (world_path_m * 1000.0 / raster_path_px) if raster_path_px > 0.0 else None
    return {
        "schema": "grand-bruxelles-civ1-rendered-sole-world-correlation-v1",
        "diagnostic_only": True,
        "candidate_samples": CANDIDATE,
        "world_horizontal_path_m": world_path_m,
        "raster_centroid_path_px": raster_path_px,
        "raster_bottom_row_span_px": bottom_span_px,
        "world_min_clearance_m": min_clearance_m,
        "world_max_clearance_m": max_clearance_m,
        "motion_observed_in_both_spaces": motion_in_both,
        "world_mm_per_raster_px": mm_per_px,
        "calibrated_player_distance_m": None,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "ground_contact_claimed": False,
        "runtime_authorized": False,
        "animation_correction_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_MOTION_CORRELATED_PLAYER_DISTANCE_UNCALIBRATED",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: correlate_civ1_rendered_sole_motion.py RASTER.json GROUND.json OUT.json", file=sys.stderr)
        return 2
    try:
        raster = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        ground = json.loads(Path(argv[2]).read_text(encoding="utf-8"))
        if not isinstance(raster, dict) or not isinstance(ground, dict):
            raise CorrelationError("receipt root")
        result = correlate(raster, ground)
        Path(argv[3]).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    except (OSError, json.JSONDecodeError, CorrelationError) as exc:
        print(f"CIV1_RENDERED_SOLE_CORRELATION_FAIL: {exc}", file=sys.stderr)
        return 3
    ratio = result["world_mm_per_raster_px"]
    ratio_text = "n/a" if ratio is None else f"{ratio:.6f}"
    print(
        "CIV1_RENDERED_SOLE_CORRELATION_OK "
        f"world_mm={result['world_horizontal_path_m'] * 1000.0:.6f} "
        f"raster_px={result['raster_centroid_path_px']:.6f} "
        f"mm_per_px={ratio_text}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
