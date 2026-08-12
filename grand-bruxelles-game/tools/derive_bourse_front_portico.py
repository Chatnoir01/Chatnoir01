#!/usr/bin/env python3
"""Derive the camera-facing Bourse front envelope from authoritative UrbIS LoD2.

The heritage sources establish the architectural semantics (monumental stair,
six Corinthian columns, triangular pediment). This tool derives only where the
camera-facing front of the already-authoritative mesh actually sits in game
space. It does not fabricate façade dimensions or move the hero mesh.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from statistics import median
from typing import Any


def _v(raw: Any) -> tuple[float, float, float]:
    return float(raw[0]), float(raw[1]), float(raw[2])


def _sub(a, b):
    return a[0] - b[0], a[1] - b[1], a[2] - b[2]


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _norm2(x: float, z: float) -> tuple[float, float]:
    length = math.hypot(x, z)
    if length <= 1e-9:
        raise ValueError("zero horizontal vector")
    return x / length, z / length


def _dot2(a: tuple[float, float], b: tuple[float, float]) -> float:
    return a[0] * b[0] + a[1] * b[1]


def derive(hero: dict[str, Any], camera: dict[str, Any], front_band_m: float = 3.0) -> dict[str, Any]:
    if hero.get("schema") != "grand-bruxelles-urbis-hero-mesh-v1":
        raise ValueError("unsupported hero schema")
    if camera.get("schema") != "grand-bruxelles-bourse-geotagged-camera-evidence-v1":
        raise ValueError("unsupported camera evidence schema")

    center_x, center_z = [float(v) for v in camera["hero_witness"]["hero_bbox_center_game_x_z_m"]]
    camera_x, _, camera_z = [float(v) for v in camera["candidate_game_camera_transform"]["position"]]
    to_camera = _norm2(camera_x - center_x, camera_z - center_z)
    tangent = (-to_camera[1], to_camera[0])

    rows: list[dict[str, Any]] = []
    for face in hero.get("faces", []):
        if not isinstance(face, dict) or face.get("type") != "WALLSURFACE":
            continue
        for triangle in face.get("triangles", []):
            if not isinstance(triangle, list) or len(triangle) != 3:
                continue
            a, b, c = (_v(triangle[0]), _v(triangle[1]), _v(triangle[2]))
            centroid = (
                (a[0] + b[0] + c[0]) / 3.0,
                (a[1] + b[1] + c[1]) / 3.0,
                (a[2] + b[2] + c[2]) / 3.0,
            )
            normal = _cross(_sub(b, a), _sub(c, a))
            horizontal_len = math.hypot(normal[0], normal[2])
            if horizontal_len <= 1e-8:
                continue
            horizontal_normal = (normal[0] / horizontal_len, normal[2] / horizontal_len)
            # Face winding is not guaranteed by the source, so facing uses absolute alignment.
            facing_alignment = abs(_dot2(horizontal_normal, to_camera))
            depth = _dot2((centroid[0] - center_x, centroid[2] - center_z), to_camera)
            vertical_span = max(a[1], b[1], c[1]) - min(a[1], b[1], c[1])
            rows.append(
                {
                    "vertices": [a, b, c],
                    "centroid": centroid,
                    "depth": depth,
                    "facing_alignment": facing_alignment,
                    "vertical_span": vertical_span,
                }
            )

    if not rows:
        raise ValueError("no wall triangles")

    # Restrict the front reference to substantially vertical, camera-facing walls.
    facing = [row for row in rows if row["facing_alignment"] >= 0.55 and row["vertical_span"] >= 0.5]
    if not facing:
        raise ValueError("no camera-facing vertical walls")
    max_depth = max(row["depth"] for row in facing)
    front = [row for row in facing if row["depth"] >= max_depth - front_band_m]
    if not front:
        raise ValueError("front band empty")

    tangent_values: list[float] = []
    y_values: list[float] = []
    depth_values: list[float] = []
    for row in front:
        depth_values.append(float(row["depth"]))
        for x, y, z in row["vertices"]:
            tangent_values.append(_dot2((x - center_x, z - center_z), tangent))
            y_values.append(y)

    t_min = min(tangent_values)
    t_max = max(tangent_values)
    y_min = min(y_values)
    y_max = max(y_values)
    depth_median = median(depth_values)

    # Convert the median front depth back to a line point in game X/Z.
    plane_x = center_x + to_camera[0] * depth_median
    plane_z = center_z + to_camera[1] * depth_median

    return {
        "schema": "grand-bruxelles-bourse-front-portico-envelope-v1",
        "source_geometry": {
            "hero_id": hero.get("hero_id"),
            "provider": hero.get("source", {}).get("provider"),
            "dataset": hero.get("source", {}).get("dataset"),
            "crs": hero.get("source", {}).get("crs"),
            "package_sha256": hero.get("source", {}).get("package_sha256"),
        },
        "camera_evidence_schema": camera.get("schema"),
        "camera_game_position": [camera_x, float(camera["candidate_game_camera_transform"]["position"][1]), camera_z],
        "hero_center_game_x_z": [center_x, center_z],
        "to_camera_x_z": [to_camera[0], to_camera[1]],
        "front_tangent_x_z": [tangent[0], tangent[1]],
        "selection": {
            "camera_facing_alignment_min": 0.55,
            "minimum_vertical_triangle_span_m": 0.5,
            "front_band_m": front_band_m,
            "eligible_wall_triangle_count": len(facing),
            "front_band_triangle_count": len(front),
            "max_camera_depth_m": max_depth,
            "median_front_depth_m": depth_median,
        },
        "front_plane": {
            "point_game_x_z": [plane_x, plane_z],
            "tangent_min_m": t_min,
            "tangent_max_m": t_max,
            "span_m": t_max - t_min,
            "y_min_m": y_min,
            "y_max_m": y_max,
        },
        "heritage_semantics": {
            "source": "https://monument.heritage.brussels/fr/Bruxelles_Pentagone/Place_de_la_Bourse/A001/31241",
            "source_type": "official Brussels architectural heritage inventory",
            "main_facade": "monumental stair leading to a peristyle limited by six Corinthian columns carrying a triangular pediment",
            "column_count": 6,
            "stair": "monumental",
            "pediment": "triangular",
        },
        "photo_witness": {
            "source": "https://commons.wikimedia.org/wiki/File:Front_of_Brussels_Stock_Exchange_2023_cropped.jpg",
            "author": "Guy Delsaut",
            "date": "2023-09-28",
            "license": "CC BY-SA 4.0",
            "usage": "visual façade witness only; image bytes not vendored",
        },
        "runtime_approved": False,
        "realism_complete": False,
        "next_gate": "use this authoritative front envelope plus the six-column heritage fact to build a provisional façade articulation overlay, then accept only after deterministic geotagged-camera visual review",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--camera", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--front-band-m", type=float, default=3.0)
    args = parser.parse_args()

    hero = json.loads(args.hero.read_text(encoding="utf-8"))
    camera = json.loads(args.camera.read_text(encoding="utf-8"))
    report = derive(hero, camera, args.front_band_m)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
