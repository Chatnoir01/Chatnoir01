#!/usr/bin/env python3
"""Discover source-backed 500 m Lambert72 cells intersected by the current OSM road slice.

Discovery only. Full-file bytes are forensic evidence because the shared OSM slice also
contains buildings, rail and environment points that may refresh independently. Spatial
identity is locked from the exact road + corridor-anchor subset instead.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT_ROAD_SOURCE = PROJECT / "data/osm/vertical_slice_01.game.json"
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
GRID_M = 500


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def fail(message: str) -> int:
    print(f"ROAD_CELL_COVERAGE_CANDIDATES_RED: {message}")
    return 2


def project_point(point: list[Any]) -> tuple[float, float]:
    if not isinstance(point, list) or len(point) != 2:
        raise ValueError("road/anchor point must be a two-value list")
    x, z = float(point[0]), float(point[1])
    if not math.isfinite(x) or not math.isfinite(z):
        raise ValueError("road/anchor point must be finite")
    return ORIGIN_E + x, ORIGIN_N - z


def grid_origin(value: float) -> int:
    return math.floor(value / GRID_M) * GRID_M


def grid_id(e0: int, n0: int) -> str:
    return f"E{e0}_N{n0}"


def bbox_for(e0: int, n0: int) -> list[float]:
    return [float(e0), float(n0), float(e0 + GRID_M), float(n0 + GRID_M)]


def segment_intersects_bbox(a: tuple[float, float], b: tuple[float, float], bbox: list[float]) -> bool:
    x0, y0 = a
    x1, y1 = b
    dx, dy = x1 - x0, y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - bbox[0], bbox[2] - x0, y0 - bbox[1], bbox[3] - y0)
    u0, u1 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if pi == 0.0:
            if qi < 0.0:
                return False
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u1:
                return False
            u0 = max(u0, t)
        else:
            if t < u0:
                return False
            u1 = min(u1, t)
    return u0 <= u1


def intersected_grid_cells(projected: list[tuple[float, float]]) -> dict[tuple[int, int], dict[str, int]]:
    hits: dict[tuple[int, int], dict[str, int]] = defaultdict(lambda: {"point_hits": 0, "segment_hits": 0})
    for e, n in projected:
        hits[(grid_origin(e), grid_origin(n))]["point_hits"] += 1
    for a, b in zip(projected, projected[1:]):
        for e0 in range(grid_origin(min(a[0], b[0])), grid_origin(max(a[0], b[0])) + GRID_M, GRID_M):
            for n0 in range(grid_origin(min(a[1], b[1])), grid_origin(max(a[1], b[1])) + GRID_M, GRID_M):
                if segment_intersects_bbox(a, b, bbox_for(e0, n0)):
                    hits[(e0, n0)]["segment_hits"] += 1
    return dict(hits)


def road_semantic_basis(payload: dict[str, Any]) -> dict[str, Any]:
    """Only fields that can change road/cell discovery belong in the stable source lock."""
    roads = payload.get("roads")
    anchors = payload.get("corridor", {}).get("anchors")
    if not isinstance(roads, list) or not roads:
        raise ValueError("road source has no roads")
    if not isinstance(anchors, list) or not anchors:
        raise ValueError("corridor anchors missing")
    return {
        "format": payload.get("format"),
        "source": payload.get("source"),
        "license": payload.get("license"),
        "stats_roads": payload.get("stats", {}).get("roads"),
        "roads": roads,
        "corridor_anchors": anchors,
    }


def discover_from_payload(payload: dict[str, Any], source_sha: str) -> dict[str, Any]:
    if payload.get("format") != "grand-bruxelles-osm-v1":
        raise ValueError("road source format drift")
    if payload.get("source") != "OpenStreetMap contributors via Overpass API":
        raise ValueError("road source provider drift")
    if payload.get("license") != "ODbL-1.0":
        raise ValueError("road source license drift")
    if len(source_sha) != 64 or any(c not in "0123456789abcdef" for c in source_sha):
        raise ValueError("road source SHA-256 must be lowercase 64-hex")

    roads = payload.get("roads")
    if not isinstance(roads, list) or not roads:
        raise ValueError("road source has no roads")
    expected_count = payload.get("stats", {}).get("roads")
    if expected_count != len(roads):
        raise ValueError(f"road count drift: stats={expected_count} actual={len(roads)}")
    road_semantic_sha = canonical_sha256(road_semantic_basis(payload))

    cell_roads: dict[tuple[int, int], dict[int, dict[str, Any]]] = defaultdict(dict)
    road_ids: set[int] = set()
    road_point_count = 0
    all_e: list[float] = []
    all_n: list[float] = []
    for road in roads:
        osm_id = road.get("osm_id")
        if not isinstance(osm_id, int) or osm_id in road_ids:
            raise ValueError("road OSM IDs must be unique integers")
        road_ids.add(osm_id)
        points = road.get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise ValueError(f"road {osm_id} requires at least two points")
        projected = [project_point(p) for p in points]
        road_point_count += len(projected)
        all_e.extend(p[0] for p in projected)
        all_n.extend(p[1] for p in projected)
        for key, hit_counts in intersected_grid_cells(projected).items():
            cell_roads[key][osm_id] = {
                "osm_id": osm_id,
                "name": str(road.get("name") or ""),
                "class": str(road.get("class") or ""),
                **hit_counts,
            }

    anchors = payload.get("corridor", {}).get("anchors")
    if not isinstance(anchors, list) or not anchors:
        raise ValueError("corridor anchors missing")
    anchor_ids: set[str] = set()
    anchor_cells: list[dict[str, Any]] = []
    anchors_by_cell: dict[tuple[int, int], list[str]] = defaultdict(list)
    for anchor in anchors:
        anchor_id = str(anchor.get("id") or "")
        if not anchor_id or anchor_id in anchor_ids:
            raise ValueError("corridor anchor IDs must be unique and non-empty")
        anchor_ids.add(anchor_id)
        e, n = project_point([anchor.get("x"), anchor.get("z")])
        key = (grid_origin(e), grid_origin(n))
        anchors_by_cell[key].append(anchor_id)
        anchor_cells.append({"anchor_id": anchor_id, "name": str(anchor.get("name") or ""), "lambert72": [e, n], "grid_cell_id": grid_id(*key)})

    candidates: list[dict[str, Any]] = []
    for (e0, n0), roads_here in sorted(cell_roads.items()):
        road_list = [roads_here[k] for k in sorted(roads_here)]
        candidates.append({
            "grid_cell_id": grid_id(e0, n0), "bbox": bbox_for(e0, n0),
            "road_count": len(road_list), "road_ids": [r["osm_id"] for r in road_list],
            "point_hits": sum(int(r["point_hits"]) for r in road_list),
            "segment_hits": sum(int(r["segment_hits"]) for r in road_list),
            "corridor_anchor_ids": sorted(anchors_by_cell.get((e0, n0), [])),
            "registration_authorized": False, "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False, "rendered_geometry_authorized": False,
            "collision_authorized": False, "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })

    stable_core = {
        "schema": "grand-bruxelles-road-cell-coverage-candidates-v2",
        "status": "DISCOVERED_SOURCE_ONLY",
        "road_source": "data/osm/vertical_slice_01.game.json",
        "road_semantic_sha256": road_semantic_sha,
        "road_source_provider": payload["source"], "road_source_license": payload["license"],
        "road_count": len(roads), "road_point_count": road_point_count,
        "road_lambert72_bbox": [min(all_e), min(all_n), max(all_e), max(all_n)],
        "frame": {"crs": "EPSG:31370", "origin_easting_m": ORIGIN_E, "origin_northing_m": ORIGIN_N, "formula": "E=origin_easting_m+x;N=origin_northing_m-z"},
        "grid_size_m": GRID_M, "candidate_cell_count": len(candidates),
        "corridor_anchors": sorted(anchor_cells, key=lambda v: v["anchor_id"]), "candidates": candidates,
        "municipality_assignment_authorized": False, "registration_authorized": False,
        "road_cell_mapping_authorized": False, "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False, "collision_authorized": False,
        "safe_spawn_authorized": False, "jouable_promotion_authorized": False,
    }
    result = dict(stable_core)
    result["road_source_sha256"] = source_sha  # forensic full-slice bytes; excluded from semantic identity
    result["semantic_sha256"] = canonical_sha256(stable_core)
    return result


def discover(road_source: Path) -> dict[str, Any]:
    raw = road_source.read_bytes()
    return discover_from_payload(json.loads(raw), sha256_bytes(raw))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-source", type=Path, default=DEFAULT_ROAD_SOURCE)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = discover(args.road_source.resolve())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return fail(str(exc))
    text = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    print(f"ROAD_CELL_COVERAGE_CANDIDATES_OK roads={result['road_count']} candidates={result['candidate_cell_count']} semantic_sha256={result['semantic_sha256']} road_semantic_sha256={result['road_semantic_sha256']} full_source_sha256={result['road_source_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
