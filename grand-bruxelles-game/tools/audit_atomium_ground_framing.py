#!/usr/bin/env python3
"""Audit Atomium ground-oblique framing without pretending to recover the source lens.

The geometry audit projects the documented 102 m Atomium from the registered camera.
When a conservative visible-subject witness is available from the lawful reference,
the tool also derives a *maximum* benchmark FOV consistent with that witness. This
is only a rejection/bounding test: it does not claim the exact historical focal
length, full monument bbox, crop, yaw or pitch.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


DEFAULT_MANIFEST = Path("data/reference/laeken_jette/photo_match_views.json")
DEFAULT_VIEW_ID = "atomium_ground_oblique_v1"
DEFAULT_REFERENCE_WITNESS = Path("data/reference/laeken_jette/atomium_ground_reference_witness.json")


def _find_view(doc: dict, view_id: str) -> dict:
    for view in doc.get("views", []):
        if view.get("id") == view_id:
            return view
    raise ValueError(f"view not found: {view_id}")


def _frame_fraction_for_fov(
    *, top_angle: float, bottom_angle: float, target_angle: float, fov_deg: float
) -> float:
    half_fov_tan = math.tan(math.radians(fov_deg) / 2.0)
    top_ndc_half = math.tan(top_angle - target_angle) / (2.0 * half_fov_tan)
    bottom_ndc_half = math.tan(bottom_angle - target_angle) / (2.0 * half_fov_tan)
    return top_ndc_half - bottom_ndc_half


def _max_fov_for_min_fraction(
    *, top_angle: float, bottom_angle: float, target_angle: float, min_fraction: float
) -> float:
    if not (0.0 < min_fraction < 1.0):
        raise ValueError("reference witness frame fraction must be between 0 and 1")
    lo, hi = 1.01, 178.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        fraction = _frame_fraction_for_fov(
            top_angle=top_angle,
            bottom_angle=bottom_angle,
            target_angle=target_angle,
            fov_deg=mid,
        )
        if fraction >= min_fraction:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def audit_view(view: dict, reference_witness: dict | None = None) -> dict:
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

    current_fraction = _frame_fraction_for_fov(
        top_angle=top_angle,
        bottom_angle=bottom_angle,
        target_angle=target_angle,
        fov_deg=fov_deg,
    )
    half_fov_tan = math.tan(math.radians(fov_deg) / 2.0)
    top_ndc_half = math.tan(top_angle - target_angle) / (2.0 * half_fov_tan)
    bottom_ndc_half = math.tan(bottom_angle - target_angle) / (2.0 * half_fov_tan)

    width_px, height_px = int(resolution[0]), int(resolution[1])
    projected_top_px = (0.5 - top_ndc_half) * height_px
    projected_bottom_px = (0.5 - bottom_ndc_half) * height_px
    projected_height_px = projected_bottom_px - projected_top_px

    result = {
        "schema": 2,
        "view_id": view["id"],
        "method": "perspective projection from registered camera/target geometry; optional conservative source-visible witness bound; no source focal-length recovery",
        "camera_to_target_horizontal_distance_m": horizontal_distance,
        "camera_y_from_atomium_baseline_m": camera_y,
        "subject_official_height_m": official_height,
        "subject_vertical_angular_span_deg": math.degrees(vertical_span),
        "camera_pitch_to_registered_target_deg": math.degrees(target_angle),
        "current_fov_degrees": fov_deg,
        "render_resolution_px": [width_px, height_px],
        "predicted_subject_bbox_y_px": [projected_top_px, projected_bottom_px],
        "predicted_subject_height_px": projected_height_px,
        "predicted_subject_frame_height_fraction": current_fraction,
        "interpretation": (
            "The current projection is deterministic. A conservative source-visible witness may reject "
            "an excessively wide FOV, but neither geometry nor the witness recovers the historical lens."
        ),
    }

    if reference_witness is not None:
        if reference_witness.get("view_id") != view["id"]:
            raise ValueError("reference witness belongs to a different view")
        source_dims = reference_witness.get("source_image_dimensions_px")
        if source_dims != view.get("reference", {}).get("source_image_dimensions_px"):
            raise ValueError("reference witness dimensions do not match registered source image")
        min_fraction = float(reference_witness["conservative_min_visible_witness_frame_fraction"])
        max_consistent_fov = _max_fov_for_min_fraction(
            top_angle=top_angle,
            bottom_angle=bottom_angle,
            target_angle=target_angle,
            min_fraction=min_fraction,
        )
        result["reference_visible_witness"] = {
            "source_image_dimensions_px": source_dims,
            "vertical_visible_witness_y_px": reference_witness["vertical_visible_witness_y_px"],
            "endpoint_uncertainty_px": reference_witness["endpoint_uncertainty_px"],
            "conservative_min_visible_witness_frame_fraction": min_fraction,
            "maximum_fov_consistent_with_visible_witness_deg": max_consistent_fov,
            "current_fov_is_too_wide": fov_deg > max_consistent_fov,
            "logic": (
                "The witness encloses only clearly visible Atomium structure, so the full 102 m monument "
                "must occupy at least this fraction of the source frame. This yields an upper bound on FOV, "
                "not an exact lens estimate."
            ),
        }

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--view-id", default=DEFAULT_VIEW_ID)
    parser.add_argument("--reference-witness", type=Path, default=DEFAULT_REFERENCE_WITNESS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    doc = json.loads(args.manifest.read_text(encoding="utf-8"))
    witness = None
    if args.reference_witness and args.reference_witness.is_file():
        witness = json.loads(args.reference_witness.read_text(encoding="utf-8"))
    result = audit_view(_find_view(doc, args.view_id), witness)
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
