#!/usr/bin/env python3
"""Measure Grand-Place road/cell identity under historical and corrected Lambert72 frames.

Evidence only. Never mutates the source and never authorizes shared frame adoption,
source merge, road-cell mapping, runtime, collision, spawn or JOUABLE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

CONTRACT_SCHEMA = "grand-bruxelles-grand-place-corrected-road-frame-cell-contract-v1"
MEASUREMENT_SCHEMA = "grand-bruxelles-grand-place-corrected-road-frame-cell-measurement-v1"
GRID_M = 500
CLOSED_AUTH = {
    "shared_frame_change_authorized": False,
    "source_refresh_authorized": False,
    "source_merge_authorized": False,
    "road_cell_mapping_authorized": False,
    "runtime_directory_scan_authorized": False,
    "runtime_mount_authorized": False,
    "rendered_geometry_authorized": False,
    "collision_authorized": False,
    "safe_spawn_authorized": False,
    "jouable_promotion_authorized": False,
}


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def finite_pair(value: Any, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} must be a 2-value list")
    a, b = float(value[0]), float(value[1])
    if not math.isfinite(a) or not math.isfinite(b):
        raise ValueError(f"{label} must be finite")
    return a, b


def project_local(origin: tuple[float, float], point: Any) -> tuple[float, float]:
    x, z = finite_pair(point, "local point")
    return origin[0] + x, origin[1] - z


def grid_origin(v: float) -> int:
    return math.floor(v / GRID_M) * GRID_M


def grid_id(point: tuple[float, float]) -> str:
    return f"E{grid_origin(point[0])}_N{grid_origin(point[1])}"


def inside(point: tuple[float, float], bbox: list[float]) -> bool:
    return bbox[0] <= point[0] <= bbox[2] and bbox[1] <= point[1] <= bbox[3]


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


def road_target_hits(road: dict[str, Any], origin: tuple[float, float], bbox: list[float]) -> dict[str, Any]:
    points = road.get("points")
    if not isinstance(points, list) or len(points) < 2:
        raise ValueError(f"road {road.get('osm_id')} requires >=2 points")
    projected = [project_local(origin, p) for p in points]
    point_hits = sum(1 for p in projected if inside(p, bbox))
    segment_hits = sum(1 for a, b in zip(projected, projected[1:]) if segment_intersects_bbox(a, b, bbox))
    return {
        "point_hits": point_hits,
        "segment_hits": segment_hits,
        "intersects_target": bool(point_hits or segment_hits),
        "lambert72_bbox": [
            round(min(p[0] for p in projected), 6),
            round(min(p[1] for p in projected), 6),
            round(max(p[0] for p in projected), 6),
            round(max(p[1] for p in projected), 6),
        ],
    }


def measure(contract: dict[str, Any], road_raw: bytes, historical: dict[str, Any], reconciliation: dict[str, Any], urbis: dict[str, Any]) -> dict[str, Any]:
    if contract.get("schema") != CONTRACT_SCHEMA:
        raise ValueError("contract schema drift")
    if contract.get("authorization") != CLOSED_AUTH:
        raise ValueError("authorization rails widened")
    deps = contract["dependencies"]
    if sha256_bytes(road_raw) != deps["road_source_sha256"]:
        raise ValueError("road source SHA drift")
    source = json.loads(road_raw)
    if source.get("format") != "grand-bruxelles-osm-v1" or source.get("license") != "ODbL-1.0":
        raise ValueError("road source format/license drift")
    if historical.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2":
        raise ValueError("historical coverage schema drift")
    if historical.get("semantic_sha256") != deps["historical_coverage_semantic_sha256"]:
        raise ValueError("historical coverage semantic drift")
    if reconciliation.get("schema") != "grand-bruxelles-osm-road-extension-reconciliation-v1":
        raise ValueError("reconciliation schema drift")
    if reconciliation.get("locked_measurement", {}).get("semantic_sha256") != deps["reconciliation_semantic_sha256"]:
        raise ValueError("reconciliation semantic drift")
    if reconciliation.get("review_verdict", {}).get("status") != "HOLD_FRAME_RECONCILIATION_REQUIRED":
        raise ValueError("reconciliation verdict drift")
    if reconciliation.get("review_verdict", {}).get("projected_source_origin_frame_is_supported_candidate") is not True:
        raise ValueError("corrected frame candidate no longer supported")
    if reconciliation.get("review_verdict", {}).get("projected_source_origin_frame_authorized_for_production") is not False:
        raise ValueError("corrected frame unexpectedly authorized")
    if urbis.get("schema") != "grand-bruxelles-urbis-source-cell-acquisition-contract-v1":
        raise ValueError("UrbIS contract schema drift")

    target = contract["target"]
    bbox = [float(v) for v in target["bbox"]]
    if urbis.get("target", {}).get("cell_id") != target["urbis_cell_id"] or urbis.get("target", {}).get("bbox") != bbox:
        raise ValueError("UrbIS target cell drift")
    official = finite_pair(urbis["identity_dependency"]["official_anchor_epsg31370"], "official anchor")
    if list(official) != deps["official_anchor_epsg31370"]:
        raise ValueError("official anchor drift")

    historical_origin = (
        float(historical["frame"]["origin_easting_m"]),
        float(historical["frame"]["origin_northing_m"]),
    )
    corrected_origin = finite_pair(
        reconciliation["locked_measurement"]["frame_comparison"]["projected_source_origin_lambert72"],
        "corrected origin",
    )

    anchors = source.get("corridor", {}).get("anchors")
    if not isinstance(anchors, list):
        raise ValueError("corridor anchors missing")
    gp = next((a for a in anchors if a.get("id") == "grand_place"), None)
    if not isinstance(gp, dict):
        raise ValueError("grand_place anchor missing")
    local_anchor = [float(gp["x"]), float(gp["z"])]
    historical_anchor = project_local(historical_origin, local_anchor)
    corrected_anchor = project_local(corrected_origin, local_anchor)

    roads = source.get("roads")
    if not isinstance(roads, list) or len(roads) != 140:
        raise ValueError("expected locked 140-road slice")
    seen: set[int] = set()
    by_id: dict[int, dict[str, Any]] = {}
    historical_target: list[dict[str, Any]] = []
    corrected_target: list[dict[str, Any]] = []
    for road in roads:
        osm_id = int(road["osm_id"])
        if osm_id in seen:
            raise ValueError(f"duplicate road id {osm_id}")
        seen.add(osm_id)
        by_id[osm_id] = road
        old = road_target_hits(road, historical_origin, bbox)
        new = road_target_hits(road, corrected_origin, bbox)
        if old["intersects_target"]:
            historical_target.append({"osm_id": osm_id, "name": str(road.get("name") or ""), **old})
        if new["intersects_target"]:
            corrected_target.append({"osm_id": osm_id, "name": str(road.get("name") or ""), **new})

    representative: list[dict[str, Any]] = []
    for spec in contract["representative_roads"]:
        osm_id = int(spec["osm_id"])
        road = by_id.get(osm_id)
        if road is None:
            raise ValueError(f"representative road {osm_id} missing")
        if road.get("name") != spec["name"]:
            raise ValueError(f"representative road {osm_id} name drift")
        representative.append({
            "osm_id": osm_id,
            "name": spec["name"],
            "historical_frame": road_target_hits(road, historical_origin, bbox),
            "corrected_frame_candidate": road_target_hits(road, corrected_origin, bbox),
        })

    historical_target.sort(key=lambda r: r["osm_id"])
    corrected_target.sort(key=lambda r: r["osm_id"])
    official_distance = math.dist(corrected_anchor, official)
    measurement: dict[str, Any] = {
        "schema": MEASUREMENT_SCHEMA,
        "status": "MEASURED_GRAND_PLACE_FRAME_CELL_EVIDENCE_ONLY",
        "production_base_sha": contract["production_base_sha"],
        "target": target,
        "inputs": {
            "road_source_sha256": deps["road_source_sha256"],
            "historical_coverage_semantic_sha256": deps["historical_coverage_semantic_sha256"],
            "reconciliation_semantic_sha256": deps["reconciliation_semantic_sha256"],
        },
        "frames": {
            "historical_origin_lambert72": [historical_origin[0], historical_origin[1]],
            "corrected_origin_candidate_lambert72": [corrected_origin[0], corrected_origin[1]],
        },
        "anchor": {
            "local_xz": local_anchor,
            "official_lambert72": [official[0], official[1]],
            "official_grid_cell_id": grid_id(official),
            "historical_lambert72": [round(historical_anchor[0], 6), round(historical_anchor[1], 6)],
            "historical_grid_cell_id": grid_id(historical_anchor),
            "historical_inside_target": inside(historical_anchor, bbox),
            "corrected_lambert72": [round(corrected_anchor[0], 6), round(corrected_anchor[1], 6)],
            "corrected_grid_cell_id": grid_id(corrected_anchor),
            "corrected_inside_target": inside(corrected_anchor, bbox),
            "corrected_to_official_delta_m": [round(corrected_anchor[0] - official[0], 6), round(corrected_anchor[1] - official[1], 6)],
            "corrected_to_official_distance_m": round(official_distance, 6),
        },
        "road_accounting": {
            "source_road_count": len(roads),
            "historical_target_intersecting_road_count": len(historical_target),
            "corrected_target_intersecting_road_count": len(corrected_target),
            "historical_target_road_ids": [r["osm_id"] for r in historical_target],
            "corrected_target_road_ids": [r["osm_id"] for r in corrected_target],
        },
        "historical_target_roads": historical_target,
        "corrected_target_roads": corrected_target,
        "representative_roads": representative,
        "verdict": {
            "historical_frame_matches_official_grand_place_cell": False,
            "corrected_frame_candidate_matches_official_grand_place_cell": grid_id(corrected_anchor) == target["grid_cell_id"] == grid_id(official),
            "shared_frame_adoption_decision": "HOLD_SEPARATE_REVIEW_REQUIRED",
            "reason": "Grand-Place-only evidence proves cell identity under the supported corrected candidate; shared frame adoption remains outside this lot.",
        },
        "authorization": dict(CLOSED_AUTH),
    }
    semantic = dict(measurement)
    semantic.pop("production_base_sha", None)
    measurement["semantic_sha256"] = canonical_sha(semantic)
    return measurement


def validate(m: dict[str, Any]) -> None:
    if m.get("schema") != MEASUREMENT_SCHEMA or m.get("authorization") != CLOSED_AUTH:
        raise ValueError("measurement schema/rails drift")
    if m["anchor"]["official_grid_cell_id"] != "E148500_N170500":
        raise ValueError("official anchor no longer in target cell")
    if m["anchor"]["historical_grid_cell_id"] != "E148000_N170000":
        raise ValueError("historical anchor cell changed unexpectedly")
    if m["anchor"]["corrected_grid_cell_id"] != "E148500_N170500":
        raise ValueError("corrected anchor not in target cell")
    if m["anchor"]["corrected_to_official_distance_m"] >= 10.0:
        raise ValueError("corrected anchor is too far from official anchor")
    reps = {r["osm_id"]: r for r in m["representative_roads"]}
    if reps[13842686]["historical_frame"]["point_hits"] != 0 or reps[13842686]["historical_frame"]["segment_hits"] != 0:
        raise ValueError("Amigo unexpectedly hits target under historical frame")
    if reps[13842686]["corrected_frame_candidate"]["point_hits"] != 6 or reps[13842686]["corrected_frame_candidate"]["segment_hits"] != 5:
        raise ValueError("Amigo corrected target hit accounting drift")
    if reps[684214770]["historical_frame"]["point_hits"] != 0 or reps[684214770]["historical_frame"]["segment_hits"] != 0:
        raise ValueError("Marché au Charbon unexpectedly hits target under historical frame")
    if reps[684214770]["corrected_frame_candidate"]["point_hits"] != 3 or reps[684214770]["corrected_frame_candidate"]["segment_hits"] != 2:
        raise ValueError("Marché au Charbon corrected target hit accounting drift")
    semantic = dict(m)
    actual = semantic.pop("semantic_sha256", None)
    semantic.pop("production_base_sha", None)
    if actual != canonical_sha(semantic):
        raise ValueError("semantic SHA mismatch")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--contract", type=Path, required=True)
    p.add_argument("--road-source", type=Path, required=True)
    p.add_argument("--historical-coverage", type=Path, required=True)
    p.add_argument("--reconciliation", type=Path, required=True)
    p.add_argument("--urbis-contract", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    try:
        m = measure(load(a.contract), a.road_source.read_bytes(), load(a.historical_coverage), load(a.reconciliation), load(a.urbis_contract))
        validate(m)
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"GRAND_PLACE_CORRECTED_ROAD_FRAME_CELL_RED: {exc}")
        return 2
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(m, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CORRECTED_ROAD_FRAME_CELL_OK "
        f"historical_cell={m['anchor']['historical_grid_cell_id']} corrected_cell={m['anchor']['corrected_grid_cell_id']} "
        f"official_distance_m={m['anchor']['corrected_to_official_distance_m']} "
        f"corrected_roads={m['road_accounting']['corrected_target_intersecting_road_count']} "
        f"semantic_sha256={m['semantic_sha256']} shared_frame_change_authorized=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
