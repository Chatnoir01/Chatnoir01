#!/usr/bin/env python3
"""Diagnose raw UrbIS triangle winding versus Grand-Place runtime orientation.

This is evidence-only: it never rewrites source geometry or runtime assets. It
reproduces the orientation rules in grand_place_complete_contour_runtime.gd so
we can distinguish source-facing facts from runtime winding decisions.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable

EPS = 1.0e-12


def vec(raw: object) -> tuple[float, float, float]:
    if not isinstance(raw, list) or len(raw) != 3:
        raise ValueError("malformed 3D point")
    value = tuple(float(v) for v in raw)
    if not all(math.isfinite(v) for v in value):
        raise ValueError("non-finite 3D point")
    return value  # type: ignore[return-value]


def sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a: tuple[float, float, float], scalar: float) -> tuple[float, float, float]:
    return (a[0] * scalar, a[1] * scalar, a[2] * scalar)


def dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length_sq(a: tuple[float, float, float]) -> float:
    return dot(a, a)


def normalized(a: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(length_sq(a))
    if length <= 0.0 or not math.isfinite(length):
        raise ValueError("cannot normalize zero/non-finite vector")
    return mul(a, 1.0 / length)


def triangles_for_type(faces: list[object], face_type: str) -> Iterable[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]]:
    for raw_face in faces:
        if not isinstance(raw_face, dict) or str(raw_face.get("type", "")) != face_type:
            continue
        raw_triangles = raw_face.get("triangles", [])
        if not isinstance(raw_triangles, list):
            raise ValueError(f"malformed triangle collection for {face_type}")
        for raw_triangle in raw_triangles:
            if not isinstance(raw_triangle, list) or len(raw_triangle) != 3:
                raise ValueError(f"malformed triangle for {face_type}")
            yield vec(raw_triangle[0]), vec(raw_triangle[1]), vec(raw_triangle[2])


def building_center(faces: list[object]) -> tuple[float, float, float]:
    total = (0.0, 0.0, 0.0)
    count = 0
    for raw_face in faces:
        if not isinstance(raw_face, dict):
            raise ValueError("malformed face")
        raw_triangles = raw_face.get("triangles", [])
        if not isinstance(raw_triangles, list):
            raise ValueError("malformed triangle collection")
        for raw_triangle in raw_triangles:
            if not isinstance(raw_triangle, list) or len(raw_triangle) != 3:
                raise ValueError("malformed triangle")
            for raw_point in raw_triangle:
                total = add(total, vec(raw_point))
                count += 1
    if count <= 0:
        raise ValueError("source contains no vertices")
    return mul(total, 1.0 / count)


def facing_stats(triangles: Iterable[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]], camera: tuple[float, float, float], center: tuple[float, float, float], face_type: str) -> dict[str, float | int]:
    triangle_count = 0
    raw_front_count = 0
    runtime_front_count = 0
    flipped_count = 0
    total_area = 0.0
    raw_front_area = 0.0
    runtime_front_area = 0.0
    for a, b, c in triangles:
        n_cross = cross(sub(b, a), sub(c, a))
        cross_sq = length_sq(n_cross)
        if cross_sq <= EPS or not math.isfinite(cross_sq):
            continue
        cross_len = math.sqrt(cross_sq)
        area = cross_len * 0.5
        normal = mul(n_cross, 1.0 / cross_len)
        tri_center = mul(add(add(a, b), c), 1.0 / 3.0)
        to_camera = sub(camera, tri_center)
        if length_sq(to_camera) <= EPS:
            raise ValueError("camera lies on a source triangle center")
        to_camera_n = normalized(to_camera)
        triangle_count += 1
        total_area += area
        if dot(normal, to_camera_n) > 0.0:
            raw_front_count += 1
            raw_front_area += area
        flip = False
        if face_type == "ROOFSURFACE":
            flip = normal[1] < 0.0
        elif face_type == "WALLSURFACE":
            outward = (tri_center[0] - center[0], 0.0, tri_center[2] - center[2])
            horizontal_normal = (normal[0], 0.0, normal[2])
            if length_sq(outward) > 0.0001 and length_sq(horizontal_normal) > 0.0001:
                flip = dot(horizontal_normal, outward) < 0.0
        else:
            raise ValueError(f"unsupported face type {face_type}")
        runtime_normal = mul(normal, -1.0) if flip else normal
        if flip:
            flipped_count += 1
        if dot(runtime_normal, to_camera_n) > 0.0:
            runtime_front_count += 1
            runtime_front_area += area
    if triangle_count <= 0 or total_area <= 0.0:
        raise ValueError(f"no non-degenerate {face_type} triangles")
    return {"triangles":triangle_count,"raw_front_triangles":raw_front_count,"runtime_oriented_front_triangles":runtime_front_count,"triangles_flipped":flipped_count,"total_area_m2":total_area,"raw_front_area_ratio":raw_front_area/total_area,"runtime_oriented_front_area_ratio":runtime_front_area/total_area}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--camera", nargs=3, type=float, required=True, metavar=("X","Y","Z"))
    args = parser.parse_args()
    data = json.loads(args.source.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit("source JSON must be an object")
    source = data.get("source", {})
    if not isinstance(source, dict):
        raise SystemExit("source provenance must be an object")
    building_id = str(source.get("building_2d_id", ""))
    owner_id = building_id.rsplit("/", 1)[-1]
    if owner_id != "1654360":
        raise SystemExit(f"unexpected owner identity: {owner_id!r}")
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        raise SystemExit("Maison du Roi source provenance drifted")
    faces = data.get("faces", [])
    if not isinstance(faces, list) or not faces:
        raise SystemExit("Maison du Roi source faces are missing")
    camera = tuple(float(v) for v in args.camera)
    if not all(math.isfinite(v) for v in camera):
        raise SystemExit("camera contains non-finite coordinates")
    center = building_center(faces)
    wall = facing_stats(triangles_for_type(faces, "WALLSURFACE"), camera, center, "WALLSURFACE")
    roof = facing_stats(triangles_for_type(faces, "ROOFSURFACE"), camera, center, "ROOFSURFACE")
    wall_loss = float(wall["raw_front_area_ratio"]) - float(wall["runtime_oriented_front_area_ratio"])
    roof_loss = float(roof["raw_front_area_ratio"]) - float(roof["runtime_oriented_front_area_ratio"])
    report = {"schema":"grand-bruxelles-grand-place-source-winding-diagnostic-v1","owner_id":owner_id,"camera_position":list(camera),"building_center":list(center),"wall_triangles":wall["triangles"],"roof_triangles":roof["triangles"],"raw_front_wall_triangles":wall["raw_front_triangles"],"raw_front_roof_triangles":roof["raw_front_triangles"],"runtime_oriented_front_wall_triangles":wall["runtime_oriented_front_triangles"],"runtime_oriented_front_roof_triangles":roof["runtime_oriented_front_triangles"],"wall_triangles_flipped_by_center_heuristic":wall["triangles_flipped"],"roof_triangles_flipped_upward":roof["triangles_flipped"],"raw_front_wall_area_ratio":wall["raw_front_area_ratio"],"raw_front_roof_area_ratio":roof["raw_front_area_ratio"],"runtime_oriented_front_wall_area_ratio":wall["runtime_oriented_front_area_ratio"],"runtime_oriented_front_roof_area_ratio":roof["runtime_oriented_front_area_ratio"],"wall_front_area_ratio_loss_due_to_runtime_orientation":wall_loss,"roof_front_area_ratio_loss_due_to_runtime_orientation":roof_loss,"source_geometry_changed":False,"source_collision_changed":False}
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
