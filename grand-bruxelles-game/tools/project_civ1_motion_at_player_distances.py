#!/usr/bin/env python3
"""Project measured CIV-1 world drift into a calibrated 1280x720 camera.

This is a capture-planning oracle only. It computes the pinhole projection signal
that a future real Godot 2/4/8 m witness should resolve. It never claims that the
predicted pixels were observed, never infers perceptibility, and never authorizes
an animation correction.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

DISTANCES_M = (2.0, 4.0, 8.0)
WIDTH = 1280
HEIGHT = 720
VERTICAL_FOV_DEG = 45.0
EXPECTED_CORRELATION_SCHEMA = "grand-bruxelles-civ1-rendered-sole-world-correlation-v1"


def horizontal_focal_px(width: int, height: int, vertical_fov_deg: float) -> float:
    if width <= 0 or height <= 0 or not (0.0 < vertical_fov_deg < 180.0):
        raise ValueError("invalid camera geometry")
    vfov = math.radians(vertical_fov_deg)
    fy = (height / 2.0) / math.tan(vfov / 2.0)
    return fy


def project(correlation: dict) -> dict:
    if correlation.get("schema") != EXPECTED_CORRELATION_SCHEMA:
        raise ValueError("wrong correlation schema")
    world_path = float(correlation.get("world_horizontal_path_m", math.nan))
    if not math.isfinite(world_path) or world_path < 0.0:
        raise ValueError("invalid world path")
    if correlation.get("candidate_samples") != [115, 116, 117, 118]:
        raise ValueError("candidate sample drift")
    forbidden = (
        "planted_contact_claimed",
        "rendered_sole_contact_claimed",
        "ground_contact_claimed",
        "runtime_authorized",
        "animation_correction_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
        "perceptual_2_8m_claimed",
    )
    if any(bool(correlation.get(k, False)) for k in forbidden):
        raise ValueError("upstream evidence promoted beyond diagnostic scope")

    focal_px = horizontal_focal_px(WIDTH, HEIGHT, VERTICAL_FOV_DEG)
    rows = []
    for distance in DISTANCES_M:
        angle_rad = math.atan2(world_path, distance)
        projected_px = focal_px * world_path / distance
        rows.append(
            {
                "distance_m": distance,
                "expected_angular_motion_rad": angle_rad,
                "expected_angular_motion_arcmin": math.degrees(angle_rad) * 60.0,
                "expected_horizontal_motion_px": projected_px,
                "real_raster_observed": False,
            }
        )

    if not all(rows[i]["expected_horizontal_motion_px"] > rows[i + 1]["expected_horizontal_motion_px"] for i in range(len(rows) - 1)):
        raise ValueError("distance projection is not strictly decreasing")

    return {
        "schema": "grand-bruxelles-civ1-player-distance-projection-plan-v1",
        "diagnostic_only": True,
        "source_semantic": "pinhole_projection_plan_from_measured_world_motion_not_raster_evidence",
        "candidate_samples": [115, 116, 117, 118],
        "world_horizontal_path_m": world_path,
        "resolution": [WIDTH, HEIGHT],
        "vertical_fov_deg": VERTICAL_FOV_DEG,
        "camera_distances_m": list(DISTANCES_M),
        "focal_length_px": focal_px,
        "projections": rows,
        "actual_2_4_8m_rasters_present": False,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "ground_contact_claimed": False,
        "runtime_authorized": False,
        "animation_correction_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_DISTANCE_CAPTURE_SIGNAL_PLANNED_REAL_RASTER_REQUIRED",
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: project_civ1_motion_at_player_distances.py CORRELATION.json OUT.json", file=sys.stderr)
        return 2
    try:
        correlation = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        report = project(correlation)
        Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_DISTANCE_PROJECTION_FAIL: {exc}", file=sys.stderr)
        return 3
    values = ", ".join(f"{r['distance_m']:g}m={r['expected_horizontal_motion_px']:.3f}px" for r in report["projections"])
    print(f"CIV1_DISTANCE_PROJECTION_OK {values}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
