#!/usr/bin/env python3
"""Identify the production OSM building block nearest the official Brasseurs wall.

Evidence-only diagnostic. It reads the exact committed vertical-slice payload and
compares every selected OSM building footprint with the exact UrbIS front-wall
segment for Maison des Brasseurs (building 1639974 / wall 10945501). It does
not mutate geometry or infer survey equivalence.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"

URBIS_BUILDING_ID = "1639974"
URBIS_WALL_ID = "10945501"
WALL_A = (317.93637041315284, -487.48588343904734)
WALL_B = (325.884743245733, -483.8294664611034)
MID = ((WALL_A[0] + WALL_B[0]) * 0.5, (WALL_A[1] + WALL_B[1]) * 0.5)


def point_segment_distance(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    vx, vz = b[0] - a[0], b[1] - a[1]
    wx, wz = p[0] - a[0], p[1] - a[1]
    vv = vx * vx + vz * vz
    if vv <= 1e-18:
        return math.hypot(wx, wz)
    t = max(0.0, min(1.0, (wx * vx + wz * vz) / vv))
    q = (a[0] + t * vx, a[1] + t * vz)
    return math.hypot(p[0] - q[0], p[1] - q[1])


def orient(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def on_segment(a: tuple[float, float], b: tuple[float, float], p: tuple[float, float]) -> bool:
    return (
        min(a[0], b[0]) - 1e-9 <= p[0] <= max(a[0], b[0]) + 1e-9
        and min(a[1], b[1]) - 1e-9 <= p[1] <= max(a[1], b[1]) + 1e-9
        and abs(orient(a, b, p)) <= 1e-9
    )


def segments_intersect(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> bool:
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    if (o1 > 0 > o2 or o2 > 0 > o1) and (o3 > 0 > o4 or o4 > 0 > o3):
        return True
    return on_segment(a, b, c) or on_segment(a, b, d) or on_segment(c, d, a) or on_segment(c, d, b)


def segment_segment_distance(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> float:
    if segments_intersect(a, b, c, d):
        return 0.0
    return min(
        point_segment_distance(a, c, d),
        point_segment_distance(b, c, d),
        point_segment_distance(c, a, b),
        point_segment_distance(d, a, b),
    )


def point_in_polygon(p: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(ring) - 1
    for i, pi in enumerate(ring):
        pj = ring[j]
        if on_segment(pj, pi, p):
            return True
        if ((pi[1] > p[1]) != (pj[1] > p[1])):
            x_hit = (pj[0] - pi[0]) * (p[1] - pi[1]) / (pj[1] - pi[1]) + pi[0]
            if p[0] < x_hit:
                inside = not inside
        j = i
    return inside


def polygon_point_distance(p: tuple[float, float], ring: list[tuple[float, float]]) -> float:
    if point_in_polygon(p, ring):
        return 0.0
    return min(point_segment_distance(p, ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring)))


def wall_polygon_distance(ring: list[tuple[float, float]]) -> float:
    if point_in_polygon(WALL_A, ring) or point_in_polygon(WALL_B, ring) or point_in_polygon(MID, ring):
        return 0.0
    return min(segment_segment_distance(WALL_A, WALL_B, ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring)))


def main() -> int:
    payload = json.loads(SOURCE.read_text(encoding="utf-8"))
    if payload.get("format") != "grand-bruxelles-osm-v1":
        raise SystemExit("BRASSEURS_OSM_OWNER_FAIL: unexpected OSM payload format")
    buildings = payload.get("buildings")
    if not isinstance(buildings, list) or not buildings:
        raise SystemExit("BRASSEURS_OSM_OWNER_FAIL: selected building payload missing")

    rows: list[dict[str, Any]] = []
    for raw in buildings:
        if not isinstance(raw, dict):
            continue
        fp = raw.get("footprint")
        if not isinstance(fp, list) or len(fp) < 3:
            continue
        ring = [(float(p[0]), float(p[1])) for p in fp if isinstance(p, list) and len(p) >= 2]
        if len(ring) < 3:
            continue
        wall_d = wall_polygon_distance(ring)
        mid_d = polygon_point_distance(MID, ring)
        a_d = polygon_point_distance(WALL_A, ring)
        b_d = polygon_point_distance(WALL_B, ring)
        xs = [p[0] for p in ring]
        zs = [p[1] for p in ring]
        rows.append({
            "osm_id": int(raw["osm_id"]),
            "name": str(raw.get("name", "")),
            "kind": str(raw.get("kind", "")),
            "height": float(raw.get("height", 0.0)),
            "area": float(raw.get("area", 0.0)),
            "wall_segment_distance_m": wall_d,
            "wall_midpoint_distance_m": mid_d,
            "wall_a_distance_m": a_d,
            "wall_b_distance_m": b_d,
            "midpoint_inside": point_in_polygon(MID, ring),
            "bbox": [min(xs), min(zs), max(xs), max(zs)],
            "footprint_vertex_count": len(ring),
        })

    rows.sort(key=lambda r: (r["wall_segment_distance_m"], r["wall_midpoint_distance_m"], r["osm_id"]))
    nearest = rows[:10]
    if not nearest:
        raise SystemExit("BRASSEURS_OSM_OWNER_FAIL: no comparable buildings")

    winner = nearest[0]
    gap = float(nearest[1]["wall_segment_distance_m"]) - float(winner["wall_segment_distance_m"]) if len(nearest) > 1 else math.inf
    evidence = {
        "schema": "grand-bruxelles-brasseurs-osm-owner-audit-v1",
        "status": "evidence_only",
        "urbis": {
            "building_id": URBIS_BUILDING_ID,
            "front_wall_id": URBIS_WALL_ID,
            "front_wall_world_xz": [list(WALL_A), list(WALL_B)],
            "front_wall_midpoint_xz": list(MID),
        },
        "runtime_contract": {
            "generic_building_parent": "BrusselsOSM/GeneratedBuildings",
            "generic_building_node_pattern": "Building_<osm_id>",
            "generic_building_representation": "single_CSGPolygon3D_extrusion_per_OSM_footprint",
        },
        "nearest": nearest,
        "candidate": {
            "osm_id": winner["osm_id"],
            "runtime_node_name": f"Building_{winner['osm_id']}",
            "wall_segment_distance_m": winner["wall_segment_distance_m"],
            "runner_up_distance_gap_m": gap,
            "safe_to_hide_whole_building": False,
            "reason": "audit identifies the nearest monolithic generic OSM block only; it does not prove that removing the full block is safe or that a complete official replacement envelope exists",
        },
    }

    out = ROOT / "artifacts/qa/brasseurs_osm_owner_audit.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(evidence, separators=(",", ":"), sort_keys=True))
    print(
        "BRASSEURS_OSM_OWNER_AUDIT_OK "
        f"candidate={winner['osm_id']} wall_distance_m={winner['wall_segment_distance_m']:.6f} "
        f"midpoint_distance_m={winner['wall_midpoint_distance_m']:.6f} runner_up_gap_m={gap:.6f} "
        "safe_to_hide_whole_building=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
