#!/usr/bin/env python3
"""Evidence-only semantic/topology audit for Town Hall UrbIS face 10792937.

This script deliberately does not author runtime geometry or infer an architectural
motif. It proves where the face sits relative to the already-treated #783 gallery
chain and records the remaining semantic uncertainty.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data" / "qa" / "grand_place_town_hall_face_10792937_semantic.json"
OUTPUT_PATH = ROOT / "artifacts" / "qa" / "grand_place_town_hall_face_10792937_semantic.json"


def fail(message: str) -> None:
    raise SystemExit(f"TOWN_HALL_FACE_10792937_SEMANTIC_FAIL: {message}")


def load_json(path: Path) -> dict:
    if not path.is_file():
        fail(f"missing JSON: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"not an object: {path}")
    return value


def short_id(raw: object) -> str:
    return str(raw).rsplit("/", 1)[-1]


def xz_points(face: dict) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for tri in face.get("triangles", []):
        if not isinstance(tri, list) or len(tri) != 3:
            fail(f"malformed triangle in {short_id(face.get('id'))}")
        for raw in tri:
            if not isinstance(raw, list) or len(raw) != 3:
                fail(f"malformed vertex in {short_id(face.get('id'))}")
            p = (float(raw[0]), float(raw[2]))
            if all(math.dist(p, existing) > 1e-4 for existing in points):
                points.append(p)
    return points


def y_range(face: dict) -> tuple[float, float]:
    ys = [float(v[1]) for tri in face.get("triangles", []) for v in tri]
    if not ys:
        fail(f"no vertices in {short_id(face.get('id'))}")
    return min(ys), max(ys)


def segment(face: dict) -> tuple[tuple[float, float], tuple[float, float]]:
    pts = xz_points(face)
    if len(pts) != 2:
        fail(f"expected one vertical wall segment in {short_id(face.get('id'))}; got {len(pts)} XZ points")
    return pts[0], pts[1]


def vec(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    return b[0] - a[0], b[1] - a[1]


def length(v: tuple[float, float]) -> float:
    return math.hypot(v[0], v[1])


def unit(v: tuple[float, float]) -> tuple[float, float]:
    size = length(v)
    if size <= 1e-9:
        fail("zero-length wall segment")
    return v[0] / size, v[1] / size


def abs_dot(a: tuple[float, float], b: tuple[float, float]) -> float:
    ua, ub = unit(a), unit(b)
    return abs(ua[0] * ub[0] + ua[1] * ub[1])


def shared_endpoint(seg_a, seg_b, tolerance: float = 0.001) -> tuple[float, float] | None:
    for a in seg_a:
        for b in seg_b:
            if math.dist(a, b) <= tolerance:
                return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    return None


def world_xz_to_lambert(point: tuple[float, float], transform: dict) -> tuple[float, float]:
    origin = transform.get("lambert72_origin", [])
    world_origin = transform.get("world_origin", [])
    if len(origin) != 2 or len(world_origin) != 3:
        fail("invalid official coordinate transform")
    x, z = point
    source_x = float(origin[0]) + (x - float(world_origin[0]))
    source_y = float(origin[1]) + float(world_origin[2]) - z
    return source_x, source_y


def main() -> None:
    contract = load_json(CONTRACT_PATH)
    if contract.get("schema") != "grand-bruxelles-town-hall-face-semantic-audit-v1":
        fail("contract schema drift")
    hard = contract.get("hard_rules", {})
    for key in (
        "runtime_changed", "geometry_changed", "camera_changed",
        "source_vertices_changed", "exact_identity_claim_without_plan_registration",
        "realism_complete",
    ):
        if bool(hard.get(key, True)):
            fail(f"hard rule drift: {key}")

    decision = contract.get("decision_policy", {})
    for key in (
        "exact_architectural_identity_resolved", "implementation_authorized",
        "reuse_783_dimensions", "portal_depth_authorized", "tower_detail_authorized",
        "turret_detail_authorized", "statuary_authorized", "openings_authorized",
    ):
        if bool(decision.get(key, True)):
            fail(f"decision must remain fail-closed: {key}")

    target = contract.get("target", {})
    geometry = load_json(ROOT / str(target.get("official_geometry_path", "")))
    source = geometry.get("source", {})
    evidence = geometry.get("evidence", {})
    if source.get("building_2d_id") != target.get("urbis_building_id"):
        fail("building identity drift")
    if source.get("package_sha256") != target.get("package_sha256") or source.get("license") != target.get("license"):
        fail("official source provenance drift")
    if int(evidence.get("face_type_counts", {}).get("WALLSURFACE", 0)) != 62:
        fail("Town Hall WALLSURFACE count drift")

    faces = {short_id(face.get("id")): face for face in geometry.get("faces", []) if face.get("type") == "WALLSURFACE"}
    topo = contract.get("known_topology", {})
    ids = {
        "gallery": str(topo.get("already_treated_gallery_face", "")),
        "return": str(topo.get("intervening_return_face", "")),
        "target": short_id(target.get("face_id", "")),
        "next": str(topo.get("next_corner_face", "")),
    }
    for role, face_id in ids.items():
        if face_id not in faces:
            fail(f"required {role} face missing: {face_id}")

    target_face = faces[ids["target"]]
    if len(target_face.get("triangles", [])) != int(topo.get("expected_target_triangle_count", 0)):
        fail("target triangle count drift")
    target_y = y_range(target_face)
    expected_y = [float(v) for v in topo.get("expected_target_vertical_range_m", [])]
    if len(expected_y) != 2 or max(abs(target_y[i] - expected_y[i]) for i in range(2)) > 0.001:
        fail(f"target vertical range drift: {target_y}")

    segments = {role: segment(faces[face_id]) for role, face_id in ids.items()}
    vectors = {role: vec(*seg) for role, seg in segments.items()}
    spans = {role: length(v) for role, v in vectors.items()}
    expected_span = float(topo.get("expected_target_horizontal_span_m", 0.0))
    if abs(spans["target"] - expected_span) > 0.002:
        fail(f"target span drift: {spans['target']:.6f}")
    if abs(spans["return"] - float(topo.get("expected_return_span_m", 0.0))) > 0.002:
        fail(f"return span drift: {spans['return']:.6f}")

    gallery_to_return = shared_endpoint(segments["gallery"], segments["return"])
    return_to_target = shared_endpoint(segments["return"], segments["target"])
    target_to_next = shared_endpoint(segments["target"], segments["next"])
    if gallery_to_return is None or return_to_target is None or target_to_next is None:
        fail("expected gallery -> return -> target -> next source endpoint chain is broken")

    parallel_dot = abs_dot(vectors["gallery"], vectors["target"])
    perpendicular_dot = abs_dot(vectors["return"], vectors["target"])
    if parallel_dot < float(topo.get("expected_parallel_dot_with_10798452", 0.0)) - 0.00002:
        fail(f"target no longer parallel to #783 face: {parallel_dot:.8f}")
    if perpendicular_dot > float(topo.get("expected_perpendicular_abs_dot_with_return", 1.0)) + 0.0002:
        fail(f"intervening face no longer perpendicular: {perpendicular_dot:.8f}")

    target_centroid_xz = (
        (segments["target"][0][0] + segments["target"][1][0]) * 0.5,
        (segments["target"][0][1] + segments["target"][1][1]) * 0.5,
    )
    target_centroid_lambert = world_xz_to_lambert(target_centroid_xz, geometry.get("transform", {}))
    target_endpoints_lambert = [world_xz_to_lambert(p, geometry.get("transform", {})) for p in segments["target"]]
    source_bbox = evidence.get("source_bbox_xy", [])
    if len(source_bbox) != 4:
        fail("official source bbox missing")
    east_bbox_distance = float(source_bbox[2]) - target_centroid_lambert[0]
    if abs(east_bbox_distance - float(topo.get("expected_centroid_distance_from_building_east_bbox_m", 0.0))) > 0.003:
        fail(f"east-bbox relation drift: {east_bbox_distance:.6f}m")
    eastmost_endpoint_delta = min(abs(float(source_bbox[2]) - p[0]) for p in target_endpoints_lambert)
    if eastmost_endpoint_delta > 0.002:
        fail(f"target no longer reaches building east bbox: delta={eastmost_endpoint_delta:.6f}m")

    heritage = contract.get("heritage_sources", {})
    urban = heritage.get("urban_31125", {})
    if "31125" not in str(urban.get("record", "")) or len(urban.get("facts_used", [])) < 4:
        fail("urban.brussels semantic context incomplete")
    for key in ("kcml_b1499_candidate", "kcml_b1501_candidate"):
        row = heritage.get(key, {})
        if row.get("license") != "Public Domain Mark 1.0" or row.get("scale") != "1/20" or bool(row.get("used_for_dimensions_now", True)):
            fail(f"KCML candidate source policy drift: {key}")

    result = {
        "schema": "grand-bruxelles-town-hall-face-10792937-semantic-evidence-v1",
        "status": "evidence_only",
        "runtime_changed": False,
        "target_face_id": ids["target"],
        "source_triangle_count": len(target_face.get("triangles", [])),
        "target_project_xz_endpoints": [list(p) for p in segments["target"]],
        "target_lambert72_endpoints": [list(p) for p in target_endpoints_lambert],
        "target_lambert72_centroid": list(target_centroid_lambert),
        "target_horizontal_span_m": spans["target"],
        "target_vertical_range_m": list(target_y),
        "topology": {
            "gallery_face": ids["gallery"],
            "intervening_return_face": ids["return"],
            "next_corner_face": ids["next"],
            "gallery_to_return_shared_endpoint_xz": list(gallery_to_return),
            "return_to_target_shared_endpoint_xz": list(return_to_target),
            "target_to_next_shared_endpoint_xz": list(target_to_next),
            "intervening_return_span_m": spans["return"],
            "target_parallel_abs_dot_with_gallery": parallel_dot,
            "target_perpendicular_abs_dot_with_return": perpendicular_dot,
        },
        "building_bbox_relation": {
            "source_bbox_xy": source_bbox,
            "centroid_distance_from_east_bbox_m": east_bbox_distance,
            "eastmost_endpoint_delta_from_east_bbox_m": eastmost_endpoint_delta,
        },
        "semantic_result": {
            "coarse_spatial_identity": decision.get("coarse_spatial_identity_allowed"),
            "exact_architectural_identity_resolved": False,
            "supported_context": "UrbIS geometry places the face at the east-end stepped transition immediately after the shipped Grand-Place gallery chain; official heritage text identifies the east wing as the Grand-Place wing with a return along rue Charles Buls.",
            "not_proven": ["turret", "portal", "pavilion", "stair bay", "buttress", "statuary zone", "opening pattern"],
            "next_step": decision.get("next_step"),
            "implementation_authorized": False,
        },
        "candidate_archive_sources": {
            "B1499": heritage.get("kcml_b1499_candidate"),
            "B1501": heritage.get("kcml_b1501_candidate"),
        },
        "hard_rules": hard,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(
        "TOWN_HALL_FACE_10792937_SEMANTIC_OK "
        f"span={spans['target']:.6f}m return={spans['return']:.6f}m "
        f"parallel={parallel_dot:.8f} perpendicular={perpendicular_dot:.8f} "
        f"east_bbox_centroid={east_bbox_distance:.4f}m exact_identity=false"
    )


if __name__ == "__main__":
    main()
