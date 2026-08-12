#!/usr/bin/env python3
"""Audit the source-geolocated Atomium benchmark framing without guessing a lens.

This tool only uses geometry already registered in photo_match_views.json. It reports
what fraction of the rendered frame the documented 102 m Atomium would occupy at
the current benchmark camera/FOV when the camera is aimed at the registered target.
It deliberately does NOT infer the historical photographer's focal length.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


DEFAULT_MANIFEST = Path("data/reference/laeken_jette/photo_match_views.json")
DEFAULT_VIEW_ID = "atomium_ground_oblique_v1"


def _find_view(doc: dict, view_id: str) -> dict:
    for view in doc.get("views", []):
        if view.get("id") == view_id:
            return view
    raise ValueError(f"view not found: {view_id}")


def audit_view(view: dict) -> dict:
    camera_xz = view["camera_game_xz"]
    target_xyz = view["target_game_xyz"]
    camera_y = float(view["camera_game_y_from_atomium_baseline_m"])
    geometry = view["subject_geometry"]
    bottom_y = float(geometry["baseline_y_m"])
    top_y = float(geometry["top_y_m"])
    official_height = float(geometry["official_height_m"])
    fov_deg = float(view["fov_degrees"])
    resolution = view["resolution"]

    if not math.isclose(top_y - bottom_y, official_height, abs_tol=1e-6):
        raise ValueError("subject geometry height is internally inconsistent")
    if not (1.0 < fov_deg < 179.0):
        raise ValueError("FOV is outside a physically meaningful perspective range")
    if len(resolution) != 2 or min(resolution) <= 0:
        raise ValueError("invalid benchmark resolution")

    dx = float(target_xyz[0]) - float(camera_xz[0])
    dz = float(target_xyz[2]) - float(camera_xz[1])
    horizontal_distance = math.hypot(dx, dz)
    if horizontal_distance <= 0.0:
        raise ValueError("camera and target have zero horizontal separation")

    target_angle = math.atan2(float(target_xyz[1]) - camera_y, horizontal_distance)
    bottom_angle = math.atan2(bottom_y - camera_y, horizontal_distance)
    top_angle = math.atan2(top_y - camera_y, horizontal_distance)
    vertical_span = top_angle - bottom_angle

    half_fov_tan = math.tan(math.radians(fov_deg) / 2.0)
    top_ndc_half = math.tan(top_angle - target_angle) / (2.0 * half_fov_tan)
    bottom_ndc_half = math.tan(bottom_angle - target_angle) / (2.0 * half_fov_tan)
    frame_fraction = top_ndc_half - bottom_ndc_half

    width_px, height_px = int(resolution[0]), int(resolution[1])
    projected_top_px = (0.5 - top_ndc_half) * height_px
    projected_bottom_px = (0.5 - bottom_ndc_half) * height_px
    projected_height_px = projected_bottom_px - projected_top_px

    return {
        "schema": 1,
        "view_id": view["id"],
        "method": "perspective projection from registered camera/target geometry; no source focal-length inference",
        "camera_to_target_horizontal_distance_m": horizontal_distance,
        "camera_y_from_atomium_baseline_m": camera_y,
        "subject_official_height_m": official_height,
        "subject_vertical_angular_span_deg": math.degrees(vertical_span),
        "camera_pitch_to_registered_target_deg": math.degrees(target_angle),
        "current_fov_degrees": fov_deg,
        "render_resolution_px": [width_px, height_px],
        "predicted_subject_bbox_y_px": [projected_top_px, projected_bottom_px],
        "predicted_subject_height_px": projected_height_px,
        "predicted_subject_frame_height_fraction": frame_fraction,
        "interpretation": (
            "This is a deterministic geometry-only prediction for the current benchmark. "
            "It explains framing scale but cannot recover the historical lens. Reference-image "
            "bbox measurement is still required before changing the benchmark FOV."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--view-id", default=DEFAULT_VIEW_ID)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    doc = json.loads(args.manifest.read_text(encoding="utf-8"))
    result = audit_view(_find_view(doc, args.view_id))
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
