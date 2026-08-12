#!/usr/bin/env python3
"""Measure the authoritative Bourse LoD2 game-space vertical anchor.

This is a diagnostic only. It reads the already-vendored UrbIS hero mesh and
reports the actual Y distribution by semantic face type so façade work cannot
paper over a floating or vertically shifted building.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _vertices(face: dict[str, Any]):
    for triangle in face.get("triangles", []):
        if not isinstance(triangle, list) or len(triangle) != 3:
            continue
        for vertex in triangle:
            if isinstance(vertex, list) and len(vertex) == 3:
                yield [float(vertex[0]), float(vertex[1]), float(vertex[2])]


def summarize(data: dict[str, Any]) -> dict[str, Any]:
    if data.get("schema") != "grand-bruxelles-urbis-hero-mesh-v1":
        raise ValueError("unsupported hero schema")

    per_type: dict[str, dict[str, Any]] = {}
    all_y: list[float] = []
    wall_triangle_mins: list[float] = []
    wall_triangle_maxs: list[float] = []

    for face in data.get("faces", []):
        if not isinstance(face, dict):
            continue
        face_type = str(face.get("type", "UNKNOWN"))
        ys = [vertex[1] for vertex in _vertices(face)]
        if not ys:
            continue
        all_y.extend(ys)
        row = per_type.setdefault(
            face_type,
            {
                "face_count": 0,
                "vertex_count": 0,
                "y_min_m": float("inf"),
                "y_max_m": float("-inf"),
                "vertices_at_or_below_0_10m": 0,
                "vertices_at_or_below_0_50m": 0,
                "vertices_at_or_below_1_00m": 0,
            },
        )
        row["face_count"] += 1
        row["vertex_count"] += len(ys)
        row["y_min_m"] = min(row["y_min_m"], min(ys))
        row["y_max_m"] = max(row["y_max_m"], max(ys))
        row["vertices_at_or_below_0_10m"] += sum(y <= 0.10 for y in ys)
        row["vertices_at_or_below_0_50m"] += sum(y <= 0.50 for y in ys)
        row["vertices_at_or_below_1_00m"] += sum(y <= 1.00 for y in ys)

        if face_type == "WALLSURFACE":
            for triangle in face.get("triangles", []):
                if not isinstance(triangle, list) or len(triangle) != 3:
                    continue
                tri_y = [float(vertex[1]) for vertex in triangle if isinstance(vertex, list) and len(vertex) == 3]
                if len(tri_y) == 3:
                    wall_triangle_mins.append(min(tri_y))
                    wall_triangle_maxs.append(max(tri_y))

    if not all_y:
        raise ValueError("hero has no game-space vertices")

    for row in per_type.values():
        row["y_min_m"] = round(float(row["y_min_m"]), 6)
        row["y_max_m"] = round(float(row["y_max_m"]), 6)

    ground = per_type.get("GROUNDSURFACE")
    wall = per_type.get("WALLSURFACE")
    roof = per_type.get("ROOFSURFACE")

    report = {
        "schema": "grand-bruxelles-bourse-vertical-anchor-evidence-v1",
        "hero_id": data.get("hero_id"),
        "source_base_z_m": float(data.get("transform", {}).get("source_base_z", 0.0)),
        "source_z_min_m": float(data.get("evidence", {}).get("source_z_min", 0.0)),
        "source_z_max_m": float(data.get("evidence", {}).get("source_z_max", 0.0)),
        "source_height_m": float(data.get("evidence", {}).get("height_m", 0.0)),
        "game_y_min_m": round(min(all_y), 6),
        "game_y_max_m": round(max(all_y), 6),
        "game_height_m": round(max(all_y) - min(all_y), 6),
        "per_face_type": per_type,
        "ground_anchor": {
            "present": ground is not None,
            "y_min_m": None if ground is None else ground["y_min_m"],
            "y_max_m": None if ground is None else ground["y_max_m"],
        },
        "wall_base": {
            "present": wall is not None,
            "y_min_m": None if wall is None else wall["y_min_m"],
            "triangles_touching_0_10m": sum(value <= 0.10 for value in wall_triangle_mins),
            "triangles_touching_0_50m": sum(value <= 0.50 for value in wall_triangle_mins),
            "triangles_touching_1_00m": sum(value <= 1.00 for value in wall_triangle_mins),
            "triangle_count": len(wall_triangle_mins),
        },
        "roof": {
            "present": roof is not None,
            "y_min_m": None if roof is None else roof["y_min_m"],
            "y_max_m": None if roof is None else roof["y_max_m"],
        },
        "runtime_approved": False,
        "realism_complete": False,
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    data = json.loads(args.input.read_text(encoding="utf-8"))
    report = summarize(data)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    print(text, end="")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
