#!/usr/bin/env python3
"""Measure the authoritative Bourse roofline behind the reviewed front portico.

The official heritage inventory says the six-column façade carries a triangular
pediment. This tool does not invent that triangle. It projects the existing
UrbIS3D WALLSURFACE/ROOFSURFACE vertices into the already-reviewed front-plane
basis and reports depth-bounded roofline profiles so a later runtime overlay can
be tied to source geometry instead of guessed proportions.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _iter_vertices(hero: dict[str, Any], face_type: str):
    seen: set[tuple[float, float, float]] = set()
    for face in hero.get("faces", []):
        if not isinstance(face, dict) or str(face.get("type", "")) != face_type:
            continue
        for triangle in face.get("triangles", []):
            if not isinstance(triangle, list) or len(triangle) != 3:
                continue
            for raw in triangle:
                if not isinstance(raw, list) or len(raw) != 3:
                    continue
                point = (float(raw[0]), float(raw[1]), float(raw[2]))
                key = tuple(round(value, 4) for value in point)
                if key in seen:
                    continue
                seen.add(key)
                yield point


def _project(point, plane_x: float, plane_z: float, tangent, forward):
    dx = point[0] - plane_x
    dz = point[2] - plane_z
    tangent_m = dx * tangent[0] + dz * tangent[1]
    depth_m = dx * forward[0] + dz * forward[1]
    return tangent_m, depth_m


def _profile(points: list[dict[str, float]], t_min: float, t_max: float, bins: int) -> list[dict[str, Any]]:
    width = (t_max - t_min) / float(bins)
    rows: list[dict[str, Any]] = []
    for index in range(bins):
        left = t_min + width * index
        right = t_max if index == bins - 1 else left + width
        selected = [p for p in points if left <= p["tangent_m"] <= right]
        rows.append(
            {
                "index": index,
                "tangent_center_m": (left + right) * 0.5,
                "point_count": len(selected),
                "y_min_m": None if not selected else min(p["y_m"] for p in selected),
                "y_max_m": None if not selected else max(p["y_m"] for p in selected),
                "depth_min_m": None if not selected else min(p["depth_m"] for p in selected),
                "depth_max_m": None if not selected else max(p["depth_m"] for p in selected),
            }
        )
    return rows


def analyze(hero: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    if hero.get("schema") != "grand-bruxelles-urbis-hero-mesh-v1":
        raise ValueError("unsupported hero schema")
    if candidate.get("schema") != "grand-bruxelles-bourse-portico-articulation-candidate-v1":
        raise ValueError("unsupported portico candidate schema")

    source = candidate["source_contract"]
    if "triangular pediment" not in str(source.get("heritage_front_fact", "")):
        raise ValueError("triangular-pediment heritage fact missing")

    envelope = candidate["authoritative_front_envelope"]
    plane_x, plane_z = [float(v) for v in envelope["plane_point_game_x_z"]]
    forward = tuple(float(v) for v in envelope["toward_camera_x_z"])
    tangent = tuple(float(v) for v in envelope["tangent_x_z"])
    t_min = float(envelope["tangent_min_m"])
    t_max = float(envelope["tangent_max_m"])
    visual = candidate["provisional_visualization"]
    entablature_top = float(visual["entablature_center_y_m"]) + float(visual["entablature_height_m"]) * 0.5

    projected: dict[str, list[dict[str, float]]] = {"WALLSURFACE": [], "ROOFSURFACE": []}
    for face_type in projected:
        for point in _iter_vertices(hero, face_type):
            t, depth = _project(point, plane_x, plane_z, tangent, forward)
            if t < t_min - 4.0 or t > t_max + 4.0:
                continue
            if point[1] < entablature_top - 1.0:
                continue
            projected[face_type].append(
                {
                    "x_m": point[0],
                    "y_m": point[1],
                    "z_m": point[2],
                    "tangent_m": t,
                    "depth_m": depth,
                }
            )

    bands: list[dict[str, Any]] = []
    for band_m in (2.0, 4.0, 6.0, 8.0, 12.0, 16.0):
        row: dict[str, Any] = {"absolute_front_depth_band_m": band_m}
        for face_type in ("WALLSURFACE", "ROOFSURFACE"):
            selected = [p for p in projected[face_type] if abs(p["depth_m"]) <= band_m]
            row[face_type] = {
                "point_count": len(selected),
                "y_min_m": None if not selected else min(p["y_m"] for p in selected),
                "y_max_m": None if not selected else max(p["y_m"] for p in selected),
                "tangent_min_m": None if not selected else min(p["tangent_m"] for p in selected),
                "tangent_max_m": None if not selected else max(p["tangent_m"] for p in selected),
            }
        bands.append(row)

    # Eight metres is wide enough to catch source roof geometry immediately behind
    # the façade while excluding the deep central dome/roof mass from the first pass.
    profile_band_m = 8.0
    wall_profile_points = [p for p in projected["WALLSURFACE"] if abs(p["depth_m"]) <= profile_band_m]
    roof_profile_points = [p for p in projected["ROOFSURFACE"] if abs(p["depth_m"]) <= profile_band_m]
    combined = wall_profile_points + roof_profile_points
    profile = _profile(combined, t_min, t_max, 31)

    top_candidates = sorted(combined, key=lambda p: (-p["y_m"], abs(p["depth_m"]), abs(p["tangent_m"])))[:20]
    active_y = [row["y_max_m"] for row in profile if row["y_max_m"] is not None]

    return {
        "schema": "grand-bruxelles-bourse-front-roofline-evidence-v1",
        "hero_id": hero.get("hero_id"),
        "source_crs": hero.get("source", {}).get("crs"),
        "source_package_sha256": hero.get("source", {}).get("package_sha256"),
        "heritage_source": source.get("heritage_source"),
        "heritage_fact": source.get("heritage_front_fact"),
        "front_basis": {
            "plane_point_game_x_z": [plane_x, plane_z],
            "toward_camera_x_z": list(forward),
            "tangent_x_z": list(tangent),
            "tangent_min_m": t_min,
            "tangent_max_m": t_max,
            "entablature_top_y_m": entablature_top,
        },
        "candidate_source_point_counts": {key: len(value) for key, value in projected.items()},
        "depth_bands": bands,
        "profile_depth_band_m": profile_band_m,
        "roofline_profile_31_bins": profile,
        "profile_active_bin_count": sum(row["point_count"] > 0 for row in profile),
        "profile_y_min_m": None if not active_y else min(active_y),
        "profile_y_max_m": None if not active_y else max(active_y),
        "top_source_vertices": top_candidates,
        "runtime_approved": False,
        "realism_complete": False,
        "status": "source_roofline_measured_pediment_overlay_not_yet_derived",
        "next_gate": "inspect the front-depth roofline profile; derive a triangular-pediment overlay only if source vertices provide a defensible base/apex envelope distinct from the deeper dome/roof mass",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    hero = json.loads(args.hero.read_text(encoding="utf-8"))
    candidate = json.loads(args.candidate.read_text(encoding="utf-8"))
    report = analyze(hero, candidate)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
