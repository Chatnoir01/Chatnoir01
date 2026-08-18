#!/usr/bin/env python3
"""Evidence-only screen-space audit for official UrbIS building 1639974.

No runtime or rendering. Projects every official WALLSURFACE vertex through the
canonical merged #711/#753 player camera and computes an optimistic union bbox.
Because the union includes every wall regardless of real occlusion/backface, it is
an upper bound for any same-building wall subset at that camera.
"""

from __future__ import annotations

import hashlib
import json
import math
from collections import defaultdict, deque
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
BUILDING_PATH = ROOT / "data" / "urbis" / "grand_place_lod2" / "1639974.game.json"
CAMERA_PATH = ROOT / "data" / "qa" / "grand_place_clean_player_witness.json"
OUTPUT_PATH = ROOT / "artifacts" / "qa" / "brasseurs_full_building_projection.json"

EXPECTED_BUILDING_SHA256 = "7d5927902e43d74b62120436a4f928c56f33185c40428ff4c18aa15fa51b56e1"
EXPECTED_PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
TARGET_FACE_ID = "10945501"
FROZEN_WIDTH_GATE_PX = 300
FROZEN_HEIGHT_GATE_PX = 260
OBSERVED_755_BBOX_PX = (96, 287)
PROJECTION_CALIBRATION_TOLERANCE_PX = 2.0


def fail(message: str) -> None:
    raise SystemExit(f"BRASSEURS_FULL_BUILDING_PROJECTION_FAIL: {message}")


def v3(raw: object) -> tuple[float, float, float]:
    if not isinstance(raw, list) or len(raw) != 3:
        fail(f"invalid vec3: {raw!r}")
    return float(raw[0]), float(raw[1]), float(raw[2])


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, scalar: float):
    return tuple(x * scalar for x in a)


def dot(a, b) -> float:
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(a) -> float:
    return math.sqrt(dot(a, a))


def normalized(a):
    length = norm(a)
    if length <= 1e-12:
        fail("zero-length camera basis vector")
    return mul(a, 1.0 / length)


def short_face_id(face: dict) -> str:
    return str(face.get("id", "")).rsplit("/", 1)[-1]


def quantized_vertex(raw: object) -> tuple[int, int, int]:
    p = v3(raw)
    return tuple(round(value * 10000.0) for value in p)


def unique_face_vertices(face: dict) -> set[tuple[int, int, int]]:
    result: set[tuple[int, int, int]] = set()
    for triangle in face.get("triangles", []):
        if not isinstance(triangle, list) or len(triangle) != 3:
            fail(f"malformed triangle in face {short_face_id(face)}")
        for raw in triangle:
            result.add(quantized_vertex(raw))
    return result


def bbox(points: Iterable[tuple[float, float]]) -> dict:
    pts = list(points)
    if not pts:
        fail("empty projection bbox")
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    left, right = min(xs), max(xs)
    top, bottom = min(ys), max(ys)
    return {
        "left_px": left,
        "right_px": right,
        "top_px": top,
        "bottom_px": bottom,
        "width_px": right - left,
        "height_px": bottom - top,
    }


def main() -> None:
    if not BUILDING_PATH.is_file() or not CAMERA_PATH.is_file():
        fail("required building/camera source missing")

    building_bytes = BUILDING_PATH.read_bytes()
    building_sha = hashlib.sha256(building_bytes).hexdigest()
    if building_sha != EXPECTED_BUILDING_SHA256:
        fail(f"official building SHA drifted: {building_sha}")

    building = json.loads(building_bytes)
    camera = json.loads(CAMERA_PATH.read_text(encoding="utf-8"))

    if building.get("schema") != "grand-bruxelles-urbis-context-mesh-v1":
        fail("building schema drifted")
    source = building.get("source", {})
    evidence = building.get("evidence", {})
    if source.get("building_2d_id") != "https://databrussels.be/id/building/1639974":
        fail("building identity drifted")
    if source.get("license") != "CC0-1.0" or source.get("package_sha256") != EXPECTED_PACKAGE_SHA256:
        fail("building provenance drifted")
    if evidence.get("face_type_counts", {}).get("WALLSURFACE") != 6:
        fail("expected exactly six official WALLSURFACE faces")
    if bool(building.get("runtime_approved", True)):
        fail("evidence source must remain runtime_approved=false")

    if camera.get("schema") != "grand-bruxelles-grand-place-clean-player-witness-v1" or camera.get("source_pr") != 711:
        fail("canonical camera contract identity drifted")
    width, height = [int(v) for v in camera.get("resolution", [])]
    if (width, height) != (1280, 720):
        fail("canonical camera resolution drifted")
    camera_position = v3(camera.get("camera_position"))
    camera_target = v3(camera.get("camera_target"))
    fov_deg = float(camera.get("camera_fov_deg", 0.0))
    if camera_position != (319.01, 1.72, -535.20) or camera_target != (321.91, 11.8, -485.66) or abs(fov_deg - 62.0) > 1e-9:
        fail("canonical #711/#753 camera values drifted")

    forward = normalized(sub(camera_target, camera_position))
    world_up = (0.0, 1.0, 0.0)
    right = normalized(cross(forward, world_up))
    corrected_up = normalized(cross(right, forward))
    tan_v = math.tan(math.radians(fov_deg * 0.5))
    tan_h = tan_v * (width / height)

    def project(raw: object) -> tuple[float, float, float]:
        point = v3(raw)
        delta = sub(point, camera_position)
        depth = dot(delta, forward)
        if depth <= 0.001:
            fail(f"official point behind canonical camera: {point}")
        local_x = dot(delta, right)
        local_y = dot(delta, corrected_up)
        ndc_x = local_x / (depth * tan_h)
        ndc_y = local_y / (depth * tan_v)
        px = (ndc_x + 1.0) * width * 0.5
        py = (1.0 - ndc_y) * height * 0.5
        return px, py, depth

    wall_faces = [face for face in building.get("faces", []) if face.get("type") == "WALLSURFACE"]
    if len(wall_faces) != 6:
        fail(f"wall face count mismatch: {len(wall_faces)}")

    per_face = []
    all_projected: list[tuple[float, float]] = []
    face_vertices = {}
    for face in wall_faces:
        face_id = short_face_id(face)
        projected = []
        depths = []
        for triangle in face.get("triangles", []):
            for raw in triangle:
                px, py, depth = project(raw)
                projected.append((px, py))
                depths.append(depth)
        face_box = bbox(projected)
        all_projected.extend(projected)
        face_vertices[face_id] = unique_face_vertices(face)
        per_face.append(
            {
                "face_id": face_id,
                "triangle_count": len(face.get("triangles", [])),
                "bbox": face_box,
                "nearest_camera_depth_m": min(depths),
                "farthest_camera_depth_m": max(depths),
            }
        )

    # Edge-connected wall adjacency: require >=2 shared source vertices so a mere
    # corner touch does not count as one coherent wall edge.
    adjacency: dict[str, list[str]] = defaultdict(list)
    ids = sorted(face_vertices)
    for index, left_id in enumerate(ids):
        for right_id in ids[index + 1 :]:
            if len(face_vertices[left_id] & face_vertices[right_id]) >= 2:
                adjacency[left_id].append(right_id)
                adjacency[right_id].append(left_id)
    for face_id in ids:
        adjacency[face_id] = sorted(adjacency[face_id])

    rooted_component = []
    queue = deque([TARGET_FACE_ID])
    seen = {TARGET_FACE_ID}
    while queue:
        current = queue.popleft()
        rooted_component.append(current)
        for neighbor in adjacency[current]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append(neighbor)
    rooted_component.sort()

    target_row = next((row for row in per_face if row["face_id"] == TARGET_FACE_ID), None)
    if target_row is None:
        fail("target face 10945501 missing")
    target_box = target_row["bbox"]
    if abs(target_box["width_px"] - OBSERVED_755_BBOX_PX[0]) > PROJECTION_CALIBRATION_TOLERANCE_PX:
        fail(f"projection does not reproduce #755 width: {target_box['width_px']:.3f}px")
    if abs(target_box["height_px"] - OBSERVED_755_BBOX_PX[1]) > PROJECTION_CALIBRATION_TOLERANCE_PX:
        fail(f"projection does not reproduce #755 height: {target_box['height_px']:.3f}px")

    union_box = bbox(all_projected)
    max_same_building_width = union_box["width_px"]
    max_same_building_height = union_box["height_px"]
    can_meet_width_gate = max_same_building_width >= FROZEN_WIDTH_GATE_PX
    can_meet_height_gate = max_same_building_height >= FROZEN_HEIGHT_GATE_PX

    result = {
        "schema": "grand-bruxelles-brasseurs-full-building-projection-v1",
        "status": "evidence_only",
        "runtime_changed": False,
        "building": {
            "id": "1639974",
            "source_path": str(BUILDING_PATH.relative_to(ROOT)),
            "source_sha256": building_sha,
            "package_sha256": EXPECTED_PACKAGE_SHA256,
            "license": "CC0-1.0",
            "wall_surface_count": len(wall_faces),
        },
        "camera": {
            "contract_path": str(CAMERA_PATH.relative_to(ROOT)),
            "source_pr": 711,
            "position": list(camera_position),
            "target": list(camera_target),
            "fov_deg": fov_deg,
            "resolution": [width, height],
        },
        "projection_calibration": {
            "target_face_id": TARGET_FACE_ID,
            "observed_755_bbox_px": list(OBSERVED_755_BBOX_PX),
            "projected_target_bbox": target_box,
            "tolerance_px": PROJECTION_CALIBRATION_TOLERANCE_PX,
            "matches_render": True,
        },
        "per_wall_face": sorted(per_face, key=lambda row: row["face_id"]),
        "edge_adjacency": dict(sorted(adjacency.items())),
        "target_edge_connected_component": rooted_component,
        "optimistic_all_wall_union_bbox": union_box,
        "reference_frozen_755_gate": {
            "min_bbox_width_px": FROZEN_WIDTH_GATE_PX,
            "min_bbox_height_px": FROZEN_HEIGHT_GATE_PX,
        },
        "decision": {
            "all_wall_union_is_optimistic_upper_bound": True,
            "can_any_same_building_wall_subset_meet_755_width_gate": can_meet_width_gate,
            "can_all_building_walls_meet_755_height_gate": can_meet_height_gate,
            "max_same_building_wall_width_px": max_same_building_width,
            "max_same_building_wall_height_px": max_same_building_height,
            "width_gate_fraction": max_same_building_width / FROZEN_WIDTH_GATE_PX,
            "recommend_same_building_visual_retry": can_meet_width_gate,
            "reason": (
                "Even the optimistic union of all six official WALLSURFACE faces stays below the frozen 300px width gate; no same-building wall subset can be wider."
                if not can_meet_width_gate
                else "Official same-building wall geometry has enough projected width to justify a separate coherent-frontage visual experiment."
            ),
        },
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(
        "BRASSEURS_FULL_BUILDING_PROJECTION_OK "
        f"target={target_box['width_px']:.3f}x{target_box['height_px']:.3f}px "
        f"all_walls={max_same_building_width:.3f}x{max_same_building_height:.3f}px "
        f"width_gate={FROZEN_WIDTH_GATE_PX}px can_meet={str(can_meet_width_gate).lower()} "
        f"connected_faces={len(rooted_component)}"
    )


if __name__ == "__main__":
    main()
