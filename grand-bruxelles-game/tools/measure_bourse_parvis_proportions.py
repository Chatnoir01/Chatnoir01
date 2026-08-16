#!/usr/bin/env python3
"""Measure Bourse parvis/street/sidewalk proportions from source-locked geometry.

The inherited +1.8 m StreetSurface 22358 proposal is evaluated as QA-only translated
capture geometry. The persisted UrbIS polygons are never modified by this tool.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data" / "qa" / "bourse_parvis_proportions_evidence.json"
BASE_SURFACES = ROOT / "data" / "urbis" / "bourse_street_surfaces.game.json"
SIDEWALKS = ROOT / "data" / "urbis" / "bourse_official_sidewalks.game.json"
CAMERA = ROOT / "data" / "qa" / "photo_match" / "bourse_2019_geotagged_camera_evidence.json"
CURB_POLICY = ROOT / "data" / "urbis" / "bourse_curb_source_policy.game.json"
TARGET_ID = "https://databrussels.be/id/streetsurface/22358"
SHIFT_M = 1.8


def _load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _open_ring(raw: Iterable[Iterable[float]]) -> list[tuple[float, float]]:
    pts = [(float(p[0]), float(p[1])) for p in raw]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts.pop()
    if len(pts) < 3:
        raise ValueError("polygon ring must contain at least three open vertices")
    return pts


def _dot(p: tuple[float, float], axis: tuple[float, float]) -> float:
    return p[0] * axis[0] + p[1] * axis[1]


def _interval(points: list[tuple[float, float]], axis: tuple[float, float]) -> tuple[float, float]:
    values = [_dot(p, axis) for p in points]
    return min(values), max(values)


def _area(points: list[tuple[float, float]]) -> float:
    total = 0.0
    for a, b in zip(points, points[1:] + points[:1]):
        total += a[0] * b[1] - b[0] * a[1]
    return abs(total) * 0.5


def _centroid(points: list[tuple[float, float]]) -> tuple[float, float]:
    # Stable vertex centroid is sufficient for directional QA comparison; source AREA
    # remains the authoritative published area field.
    return (
        sum(p[0] for p in points) / len(points),
        sum(p[1] for p in points) / len(points),
    )


def _point_segment_distance(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    vx, vz = b[0] - a[0], b[1] - a[1]
    wx, wz = p[0] - a[0], p[1] - a[1]
    denom = vx * vx + vz * vz
    if denom <= 1e-12:
        return math.hypot(wx, wz)
    t = max(0.0, min(1.0, (wx * vx + wz * vz) / denom))
    qx, qz = a[0] + t * vx, a[1] + t * vz
    return math.hypot(p[0] - qx, p[1] - qz)


def _polygon_distance(a: list[tuple[float, float]], b: list[tuple[float, float]]) -> float:
    best = math.inf
    for p in a:
        for q0, q1 in zip(b, b[1:] + b[:1]):
            best = min(best, _point_segment_distance(p, q0, q1))
    for p in b:
        for q0, q1 in zip(a, a[1:] + a[:1]):
            best = min(best, _point_segment_distance(p, q0, q1))
    return best


def _camera_axis(camera: dict[str, Any]) -> tuple[float, float]:
    transform = camera["project_transform"]
    witness = camera["hero_witness"]
    cx, cz = (float(v) for v in transform["game_camera_x_z_m"])
    hx, hz = (float(v) for v in witness["hero_bbox_center_game_x_z_m"])
    dx, dz = hx - cx, hz - cz
    length = math.hypot(dx, dz)
    if length <= 0.0:
        raise ValueError("camera-to-hero horizontal axis is degenerate")
    return dx / length, dz / length


def _target_surface(data: dict[str, Any]) -> dict[str, Any]:
    for row in data.get("surfaces", []):
        if isinstance(row, dict) and row.get("inspire_id") == TARGET_ID:
            return row
    raise RuntimeError(f"missing target StreetSurface {TARGET_ID}")


def _sidewalk_rings(data: dict[str, Any]) -> list[tuple[str, list[tuple[float, float]]]]:
    rows: list[tuple[str, list[tuple[float, float]]]] = []
    for item in data.get("sidewalks", []):
        if not isinstance(item, dict):
            continue
        rings = item.get("world_rings_xz", [])
        if not isinstance(rings, list) or len(rings) != 1:
            continue
        rows.append((str(item.get("source_id", "unknown")), _open_ring(rings[0])))
    if not rows:
        raise RuntimeError("no official Bourse sidewalk rings available")
    return rows


def measure() -> dict[str, Any]:
    evidence = _load(EVIDENCE)
    base = _load(BASE_SURFACES)
    sidewalks = _load(SIDEWALKS)
    camera = _load(CAMERA)
    curb = _load(CURB_POLICY)

    if evidence.get("runtime_approved") is not False or evidence.get("realism_complete") is not False:
        raise ValueError("proportion evidence must stay unapproved")
    if curb["decision"]["vertical_extrusion_allowed"] is not False:
        raise ValueError("curb source policy unexpectedly allows vertical extrusion")

    axis = _camera_axis(camera)
    lateral = (-axis[1], axis[0])
    expected_axis = tuple(float(v) for v in evidence["qa_candidate"]["axis_unit_xz"])
    if math.hypot(axis[0] - expected_axis[0], axis[1] - expected_axis[1]) > 1e-9:
        raise ValueError("stored QA camera axis no longer matches geotagged camera evidence")

    target = _target_surface(base)
    rings = target.get("world_rings_xz", [])
    if not isinstance(rings, list) or len(rings) != 1:
        raise ValueError("target 22358 must have exactly one world ring")
    baseline = _open_ring(rings[0])
    shift = (axis[0] * SHIFT_M, axis[1] * SHIFT_M)
    candidate = [(p[0] + shift[0], p[1] + shift[1]) for p in baseline]
    sidewalk_rows = _sidewalk_rings(sidewalks)

    base_axis = _interval(baseline, axis)
    cand_axis = _interval(candidate, axis)
    base_lat = _interval(baseline, lateral)
    cand_lat = _interval(candidate, lateral)
    base_center = _centroid(baseline)
    cand_center = _centroid(candidate)

    nearest_base = min(
        ((source_id, _polygon_distance(baseline, ring)) for source_id, ring in sidewalk_rows),
        key=lambda row: row[1],
    )
    nearest_candidate = min(
        ((source_id, _polygon_distance(candidate, ring)) for source_id, ring in sidewalk_rows),
        key=lambda row: row[1],
    )

    return {
        "schema": "grand-bruxelles-bourse-parvis-proportions-measurement-v1",
        "target_inspire_id": TARGET_ID,
        "source_area_m2": float(target.get("area_m2", 0.0)),
        "computed_world_area_m2": _area(baseline),
        "camera_axis_unit_xz": list(axis),
        "lateral_axis_unit_xz": list(lateral),
        "baseline": {
            "axis_interval_m": list(base_axis),
            "axis_span_m": base_axis[1] - base_axis[0],
            "lateral_interval_m": list(base_lat),
            "lateral_span_m": base_lat[1] - base_lat[0],
            "vertex_centroid_xz": list(base_center),
            "nearest_official_sidewalk_source_id": nearest_base[0],
            "nearest_official_sidewalk_distance_m": nearest_base[1],
        },
        "qa_candidate": {
            "translation_m": SHIFT_M,
            "translation_xz_m": list(shift),
            "axis_interval_m": list(cand_axis),
            "axis_span_m": cand_axis[1] - cand_axis[0],
            "lateral_interval_m": list(cand_lat),
            "lateral_span_m": cand_lat[1] - cand_lat[0],
            "vertex_centroid_xz": list(cand_center),
            "nearest_official_sidewalk_source_id": nearest_candidate[0],
            "nearest_official_sidewalk_distance_m": nearest_candidate[1],
            "runtime_promotion_allowed": False,
        },
        "invariants": {
            "source_polygon_unchanged": True,
            "shape_area_delta_m2": abs(_area(candidate) - _area(baseline)),
            "axis_span_delta_m": abs((cand_axis[1] - cand_axis[0]) - (base_axis[1] - base_axis[0])),
            "lateral_span_delta_m": abs((cand_lat[1] - cand_lat[0]) - (base_lat[1] - base_lat[0])),
            "centroid_axis_translation_m": _dot(cand_center, axis) - _dot(base_center, axis),
            "curb_vertical_extrusion_allowed": False,
        },
        "human_gate": "pending",
        "runtime_approved": False,
        "realism_complete": False,
    }


def validate(result: dict[str, Any]) -> None:
    inv = result["invariants"]
    if abs(float(inv["shape_area_delta_m2"])) > 1e-6:
        raise AssertionError("candidate changes target polygon area")
    if abs(float(inv["axis_span_delta_m"])) > 1e-6:
        raise AssertionError("candidate changes target axis span")
    if abs(float(inv["lateral_span_delta_m"])) > 1e-6:
        raise AssertionError("candidate changes target lateral span")
    if not math.isclose(float(inv["centroid_axis_translation_m"]), SHIFT_M, abs_tol=1e-6):
        raise AssertionError("candidate does not translate exactly +1.8 m on the camera axis")
    if result.get("runtime_approved") is not False or result.get("realism_complete") is not False:
        raise AssertionError("QA measurement must remain unapproved")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = measure()
    validate(result)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "BOURSE_PARVIS_PROPORTIONS_OK",
        f"axis_shift={result['invariants']['centroid_axis_translation_m']:.6f}m",
        f"baseline_sidewalk_gap={result['baseline']['nearest_official_sidewalk_distance_m']:.4f}m",
        f"candidate_sidewalk_gap={result['qa_candidate']['nearest_official_sidewalk_distance_m']:.4f}m",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
