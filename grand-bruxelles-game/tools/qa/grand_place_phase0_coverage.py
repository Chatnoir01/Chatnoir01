#!/usr/bin/env python3
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data/qa/grand_place_phase0_coverage_contract.json"
OUT_PATH = ROOT / "artifacts/qa/grand_place_phase0_coverage_report.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(v):
    length = math.sqrt(dot(v, v))
    if length <= 1e-12:
        raise ValueError("zero-length vector")
    return (v[0] / length, v[1] / length, v[2] / length)


def project(point, camera, width, height, near_plane):
    position = tuple(camera["camera_position"])
    target = tuple(camera["camera_target"])
    forward = norm(sub(target, position))
    world_up = (0.0, 1.0, 0.0)
    right = norm(cross(world_up, forward))
    up = norm(cross(forward, right))
    rel = sub(tuple(point), position)
    z = dot(rel, forward)
    if z <= near_plane:
        return None
    x = dot(rel, right)
    y = dot(rel, up)
    focal = (height * 0.5) / math.tan(math.radians(float(camera["camera_fov_deg"])) * 0.5)
    sx = width * 0.5 + (x / z) * focal
    sy = height * 0.5 - (y / z) * focal
    return (sx, sy, z)


def edge(a, b, p):
    return (p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0])


def rasterize_triangle(mask, a, b, c, width, height):
    min_x = max(0, int(math.floor(min(a[0], b[0], c[0]))))
    max_x = min(width - 1, int(math.ceil(max(a[0], b[0], c[0]))))
    min_y = max(0, int(math.floor(min(a[1], b[1], c[1]))))
    max_y = min(height - 1, int(math.ceil(max(a[1], b[1], c[1]))))
    if min_x > max_x or min_y > max_y:
        return
    area = edge(a, b, c)
    if abs(area) < 1e-9:
        return
    positive = area > 0.0
    for y in range(min_y, max_y + 1):
        py = y + 0.5
        row = y * width
        for x in range(min_x, max_x + 1):
            p = (x + 0.5, py)
            e0 = edge(a, b, p)
            e1 = edge(b, c, p)
            e2 = edge(c, a, p)
            inside = (e0 >= 0 and e1 >= 0 and e2 >= 0) if positive else (e0 <= 0 and e1 <= 0 and e2 <= 0)
            if inside:
                mask.add(row + x)


def owner_metrics(owner, geometry, camera, width, height, near_plane, allowed_types):
    mask = set()
    triangle_count = 0
    projected_triangle_count = 0
    surface_counts = {}
    for face in geometry.get("faces", []):
        face_type = face.get("type")
        surface_counts[face_type] = surface_counts.get(face_type, 0) + 1
        if face_type not in allowed_types:
            continue
        for tri in face.get("triangles", []):
            if not isinstance(tri, list) or len(tri) != 3:
                continue
            triangle_count += 1
            projected = [project(p, camera, width, height, near_plane) for p in tri]
            if any(p is None for p in projected):
                continue
            projected_triangle_count += 1
            rasterize_triangle(mask, projected[0], projected[1], projected[2], width, height)
    pixels = len(mask)
    if pixels:
        xs = [idx % width for idx in mask]
        ys = [idx // width for idx in mask]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        bbox = [min_x, min_y, max_x, max_y]
        bbox_width = max_x - min_x + 1
        bbox_height = max_y - min_y + 1
        center_x = (min_x + max_x) * 0.5
        edge_margin = min(min_x, width - 1 - max_x)
        center_distance = abs(center_x - width * 0.5)
    else:
        bbox = None
        bbox_width = 0
        bbox_height = 0
        edge_margin = 0
        center_distance = None
    return {
        "id": owner["id"],
        "semantic_name": owner.get("semantic_name"),
        "semantic_status": owner.get("semantic_status"),
        "production_status": owner.get("production_status"),
        "building_id": owner["building_id"],
        "source_face_count": geometry.get("evidence", {}).get("face_count"),
        "source_surface_counts": surface_counts,
        "source_candidate_triangles": triangle_count,
        "projected_triangles": projected_triangle_count,
        "projected_union_pixels": pixels,
        "projected_union_percent_frame": pixels * 100.0 / float(width * height),
        "bbox": bbox,
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
        "horizontal_edge_margin": edge_margin,
        "bbox_center_distance_from_screen_center": center_distance,
        "measurement_authorizes_runtime": False,
    }


def main():
    contract = load_json(CONTRACT_PATH)
    if contract.get("runtime_changed") is True:
        raise SystemExit("PHASE0_COVERAGE_FAIL: runtime_changed must remain false")
    if contract.get("base_main") != "0807581e4a711d21b535a7def66f089da037a2f4":
        raise SystemExit("PHASE0_COVERAGE_FAIL: unexpected base_main")
    camera_path = ROOT / contract["camera_contract"]
    camera = load_json(camera_path)
    width, height = contract["resolution"]
    if camera.get("resolution") != [width, height]:
        raise SystemExit("PHASE0_COVERAGE_FAIL: camera resolution mismatch")
    if not camera.get("player_eye") or not camera.get("ui_mask_required") or not camera.get("dynamics_mask_required"):
        raise SystemExit("PHASE0_COVERAGE_FAIL: canonical witness hard rails missing")

    measurement = contract["measurement"]
    near_plane = float(measurement["near_plane_m"])
    allowed_types = set(measurement["surface_types"])
    results = []
    for owner in contract["owners"]:
        geometry_path = ROOT / owner["geometry_path"]
        if not geometry_path.exists():
            raise SystemExit(f"PHASE0_COVERAGE_FAIL: missing geometry {geometry_path}")
        geometry = load_json(geometry_path)
        source_id = str(geometry.get("source", {}).get("building_2d_id", ""))
        if not source_id.endswith("/" + owner["building_id"]):
            raise SystemExit(f"PHASE0_COVERAGE_FAIL: owner/source mismatch for {owner['id']}")
        results.append(owner_metrics(owner, geometry, camera, width, height, near_plane, allowed_types))

    results.sort(key=lambda item: item["projected_union_pixels"], reverse=True)
    missing = contract.get("required_missing_coverage", [])
    if not missing:
        raise SystemExit("PHASE0_COVERAGE_FAIL: missing-coverage registry must not be empty")
    if not any(item["projected_union_pixels"] > 0 for item in results):
        raise SystemExit("PHASE0_COVERAGE_FAIL: no persisted Grand-Place owner projects into canonical frame")

    report = {
        "schema": "grand-bruxelles-grand-place-phase0-coverage-report-v1",
        "base_main": contract["base_main"],
        "camera_id": camera["camera_id"],
        "resolution": [width, height],
        "measurement_kind": measurement["kind"],
        "nomination_only": True,
        "owners_ranked": results,
        "required_missing_coverage": missing,
        "phase0_complete": False,
        "next_gate": "Persist/register missing major owners, then run realistic shaded Godot probe on measured visible owners.",
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print("GRAND_PLACE_PHASE0_COVERAGE_OK")


if __name__ == "__main__":
    main()
