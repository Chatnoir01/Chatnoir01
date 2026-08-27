#!/usr/bin/env python3
"""Measure compatibility between the locked OSM E148500/N170500 extension and production roads.

Evidence only. This script never mutates the production source and never authorizes
source merge, road-cell mapping, runtime mount, rendering, collision, spawn or JOUABLE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import median
from typing import Any

from pyproj import Transformer

SCHEMA = "grand-bruxelles-osm-road-extension-reconciliation-v1"
MEASUREMENT_SCHEMA = "grand-bruxelles-osm-road-extension-reconciliation-measurement-v1"
PREDECESSOR_SHA = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXTENSION_RAW_SHA = "80544caed58414f3f3c58274659fcb9ec9487621976c263843af7c59d007b4ab"
EXTENSION_SEMANTIC_SHA = "7264a311b7688350126a9faa4a1e16eab7e7eea0cbc231217c3080488d7a41bf"
HISTORICAL_E = 147868.29422791934
HISTORICAL_N = 169538.62414926197
CLOSED_AUTHORIZATION = {
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


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return _sha256(raw)


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _finite_point(value: Any) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"invalid two-dimensional point: {value!r}")
    x, z = float(value[0]), float(value[1])
    if not math.isfinite(x) or not math.isfinite(z):
        raise ValueError(f"non-finite point: {value!r}")
    return x, z


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _same_count_metrics(source: list[tuple[float, float]], candidate: list[tuple[float, float]]) -> dict[str, Any]:
    if len(source) != len(candidate):
        raise ValueError("same-count metrics require equal point counts")

    def oriented(points: list[tuple[float, float]], orientation: str) -> dict[str, Any]:
        residuals = [_distance(a, b) for a, b in zip(source, points)]
        deltas = [(b[0] - a[0], b[1] - a[1]) for a, b in zip(source, points)]
        mean_dx = sum(v[0] for v in deltas) / len(deltas)
        mean_dz = sum(v[1] for v in deltas) / len(deltas)
        rigid_deviation = [math.hypot(dx - mean_dx, dz - mean_dz) for dx, dz in deltas]
        return {
            "orientation": orientation,
            "max_corresponding_residual_m": round(max(residuals), 6),
            "mean_corresponding_residual_m": round(sum(residuals) / len(residuals), 6),
            "mean_delta_x_m": round(mean_dx, 6),
            "mean_delta_z_m": round(mean_dz, 6),
            "max_rigid_delta_deviation_m": round(max(rigid_deviation), 6),
        }

    forward = oriented(candidate, "forward")
    reverse = oriented(list(reversed(candidate)), "reverse")
    key = lambda row: (row["max_corresponding_residual_m"], row["mean_corresponding_residual_m"], row["orientation"])
    return min((forward, reverse), key=key)


def _discrete_vertex_distance(a: list[tuple[float, float]], b: list[tuple[float, float]]) -> float:
    if not a or not b:
        raise ValueError("empty polyline")
    return max(max(min(_distance(pa, pb) for pb in b) for pa in a), max(min(_distance(pb, pa) for pa in a) for pb in b))


def compare_sequences(source: list[tuple[float, float]], candidate: list[tuple[float, float]], decimals: int = 3) -> dict[str, Any]:
    source_rounded = [(round(x, decimals), round(z, decimals)) for x, z in source]
    candidate_rounded = [(round(x, decimals), round(z, decimals)) for x, z in candidate]
    exact_forward = source_rounded == candidate_rounded
    exact_reverse = source_rounded == list(reversed(candidate_rounded))
    result: dict[str, Any] = {
        "source_point_count": len(source),
        "candidate_point_count": len(candidate),
        "exact_sequence_3dp": exact_forward or exact_reverse,
        "exact_orientation": "forward" if exact_forward else ("reverse" if exact_reverse else None),
        "discrete_vertex_distance_m": round(_discrete_vertex_distance(source, candidate), 6),
    }
    if len(source) == len(candidate):
        result["same_count"] = True
        result["best_correspondence"] = _same_count_metrics(source, candidate)
    else:
        result["same_count"] = False
        result["best_correspondence"] = None
    return result


def _project_way_points(raw: dict[str, Any], transformer: Transformer) -> dict[int, list[tuple[float, float]]]:
    nodes: dict[int, tuple[float, float]] = {}
    ways: dict[int, list[int]] = {}
    for element in raw.get("elements") or []:
        if not isinstance(element, dict):
            continue
        if element.get("type") == "node":
            node_id = int(element["id"])
            if node_id in nodes:
                raise ValueError(f"duplicate node id {node_id}")
            nodes[node_id] = (float(element["lon"]), float(element["lat"]))
        elif element.get("type") == "way" and isinstance(element.get("tags"), dict) and element["tags"].get("highway"):
            way_id = int(element["id"])
            if way_id in ways:
                raise ValueError(f"duplicate highway way id {way_id}")
            refs = element.get("nodes")
            if not isinstance(refs, list) or len(refs) < 2:
                raise ValueError(f"highway way {way_id} has fewer than two nodes")
            ways[way_id] = [int(v) for v in refs]
    result: dict[int, list[tuple[float, float]]] = {}
    for way_id, refs in ways.items():
        points: list[tuple[float, float]] = []
        for ref in refs:
            if ref not in nodes:
                raise ValueError(f"way {way_id} references missing node {ref}")
            lon, lat = nodes[ref]
            e, n = transformer.transform(lon, lat)
            if not (math.isfinite(e) and math.isfinite(n)):
                raise ValueError(f"projection failed for way {way_id} node {ref}")
            points.append((round(float(e), 6), round(float(n), 6)))
        result[way_id] = points
    return result


def _raw_way_tags(raw: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for element in raw.get("elements") or []:
        if isinstance(element, dict) and element.get("type") == "way" and isinstance(element.get("tags"), dict) and element["tags"].get("highway"):
            result[int(element["id"])] = element["tags"]
    return result


def _to_local(projected: list[tuple[float, float]], origin_e: float, origin_n: float) -> list[tuple[float, float]]:
    return [(round(e - origin_e, 6), round(origin_n - n, 6)) for e, n in projected]


def _aggregate_fit(rows: list[dict[str, Any]], key: str) -> dict[str, Any]:
    metrics = [row[key]["best_correspondence"] for row in rows if row[key]["best_correspondence"] is not None]
    if not metrics:
        return {"same_count_duplicate_count": 0}
    max_residuals = [float(m["max_corresponding_residual_m"]) for m in metrics]
    mean_residuals = [float(m["mean_corresponding_residual_m"]) for m in metrics]
    dx = [float(m["mean_delta_x_m"]) for m in metrics]
    dz = [float(m["mean_delta_z_m"]) for m in metrics]
    rigid_dev = [float(m["max_rigid_delta_deviation_m"]) for m in metrics]
    return {
        "same_count_duplicate_count": len(metrics),
        "median_max_corresponding_residual_m": round(median(max_residuals), 6),
        "worst_max_corresponding_residual_m": round(max(max_residuals), 6),
        "median_mean_corresponding_residual_m": round(median(mean_residuals), 6),
        "median_mean_delta_x_m": round(median(dx), 6),
        "median_mean_delta_z_m": round(median(dz), 6),
        "worst_rigid_delta_deviation_m": round(max(rigid_dev), 6),
    }


def build_measurement(contract: dict[str, Any], predecessor_raw: bytes, extension_raw: bytes) -> dict[str, Any]:
    if contract.get("schema") != SCHEMA:
        raise ValueError("unexpected reconciliation contract schema")
    if contract.get("authorization") != CLOSED_AUTHORIZATION:
        raise ValueError("authorization rails widened")
    if _sha256(predecessor_raw) != PREDECESSOR_SHA:
        raise ValueError("predecessor source SHA drift")
    if _sha256(extension_raw) != EXTENSION_RAW_SHA:
        raise ValueError("extension raw SHA drift")

    predecessor = json.loads(predecessor_raw)
    extension = json.loads(extension_raw)
    if predecessor.get("format") != "grand-bruxelles-osm-v1" or predecessor.get("license") != "ODbL-1.0":
        raise ValueError("predecessor format/provenance drift")
    if predecessor.get("source") != "OpenStreetMap contributors via Overpass API":
        raise ValueError("predecessor provider drift")
    source_origin = predecessor.get("origin") or {}
    lon = float(source_origin["lon"])
    lat = float(source_origin["lat"])

    source_roads: dict[int, dict[str, Any]] = {}
    for road in predecessor.get("roads") or []:
        road_id = int(road["osm_id"])
        if road_id in source_roads:
            raise ValueError(f"duplicate predecessor road id {road_id}")
        points = road.get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise ValueError(f"predecessor road {road_id} invalid points")
        source_roads[road_id] = road
    if len(source_roads) != 140:
        raise ValueError(f"expected 140 predecessor roads, got {len(source_roads)}")

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    projected_origin_e, projected_origin_n = transformer.transform(lon, lat)
    projected_origin_e = round(float(projected_origin_e), 6)
    projected_origin_n = round(float(projected_origin_n), 6)
    projected_ways = _project_way_points(extension, transformer)
    tags_by_way = _raw_way_tags(extension)
    if len(projected_ways) != 591:
        raise ValueError(f"expected 591 extension highway ways, got {len(projected_ways)}")

    duplicate_ids = sorted(set(source_roads) & set(projected_ways))
    extension_only_ids = sorted(set(projected_ways) - set(source_roads))
    predecessor_only_ids = sorted(set(source_roads) - set(projected_ways))
    duplicates: list[dict[str, Any]] = []
    for road_id in duplicate_ids:
        source_road = source_roads[road_id]
        source_points = [_finite_point(p) for p in source_road["points"]]
        projected = projected_ways[road_id]
        historical_local = _to_local(projected, HISTORICAL_E, HISTORICAL_N)
        projected_origin_local = _to_local(projected, projected_origin_e, projected_origin_n)
        tags = tags_by_way[road_id]
        duplicates.append({
            "osm_id": road_id,
            "predecessor_name": source_road.get("name"),
            "predecessor_class": source_road.get("class"),
            "extension_highway": tags.get("highway"),
            "extension_name": tags.get("name"),
            "extension_name_fr": tags.get("name:fr"),
            "extension_name_nl": tags.get("name:nl"),
            "class_matches_extension_highway": source_road.get("class") == tags.get("highway"),
            "historical_coverage_frame": compare_sequences(source_points, historical_local),
            "projected_source_origin_frame": compare_sequences(source_points, projected_origin_local),
        })

    origin_delta_e = projected_origin_e - HISTORICAL_E
    origin_delta_n = projected_origin_n - HISTORICAL_N
    exact_historical = sum(row["historical_coverage_frame"]["exact_sequence_3dp"] for row in duplicates)
    exact_projected = sum(row["projected_source_origin_frame"]["exact_sequence_3dp"] for row in duplicates)
    class_mismatches = sum(not row["class_matches_extension_highway"] for row in duplicates)

    measurement: dict[str, Any] = {
        "schema": MEASUREMENT_SCHEMA,
        "status": "MEASURED_RECONCILIATION_EVIDENCE_ONLY",
        "production_base_sha": contract["production_base_sha"],
        "inputs": {
            "predecessor_path": contract["predecessor"]["path"],
            "predecessor_sha256": PREDECESSOR_SHA,
            "extension_artifact_id": contract["extension"]["artifact_id"],
            "extension_raw_sha256": EXTENSION_RAW_SHA,
            "extension_acquisition_semantic_sha256": EXTENSION_SEMANTIC_SHA,
        },
        "frame_comparison": {
            "crs": "EPSG:31370",
            "source_origin_wgs84": {"lon": lon, "lat": lat},
            "historical_coverage_origin_lambert72": [HISTORICAL_E, HISTORICAL_N],
            "projected_source_origin_lambert72": [projected_origin_e, projected_origin_n],
            "projected_minus_historical_origin_m": [round(origin_delta_e, 6), round(origin_delta_n, 6)],
            "origin_delta_magnitude_m": round(math.hypot(origin_delta_e, origin_delta_n), 6),
            "local_formula": "x=E-origin_easting_m;z=origin_northing_m-N",
        },
        "accounting": {
            "predecessor_road_count": len(source_roads),
            "extension_highway_way_count": len(projected_ways),
            "duplicate_osm_way_count": len(duplicate_ids),
            "extension_only_way_count": len(extension_only_ids),
            "predecessor_only_way_count": len(predecessor_only_ids),
            "historical_frame_exact_sequence_3dp_count": exact_historical,
            "projected_source_origin_exact_sequence_3dp_count": exact_projected,
            "duplicate_class_mismatch_count": class_mismatches,
        },
        "historical_frame_fit": _aggregate_fit(duplicates, "historical_coverage_frame"),
        "projected_source_origin_frame_fit": _aggregate_fit(duplicates, "projected_source_origin_frame"),
        "duplicate_osm_way_ids": duplicate_ids,
        "extension_only_way_ids_sha256": _canonical_sha(extension_only_ids),
        "predecessor_only_way_ids": predecessor_only_ids,
        "duplicates": duplicates,
        "interpretation": {
            "source_merge_decision": "HOLD_PENDING_REVIEW",
            "reason": "measurement only; duplicate identity and frame compatibility must be reviewed before constructing any merged source",
        },
        "authorization": dict(CLOSED_AUTHORIZATION),
    }
    semantic_basis = dict(measurement)
    semantic_basis.pop("production_base_sha", None)
    measurement["semantic_sha256"] = _canonical_sha(semantic_basis)
    return measurement


def validate_measurement(measurement: dict[str, Any]) -> None:
    if measurement.get("schema") != MEASUREMENT_SCHEMA:
        raise ValueError("unexpected measurement schema")
    if measurement.get("status") != "MEASURED_RECONCILIATION_EVIDENCE_ONLY":
        raise ValueError("measurement status widened")
    if measurement.get("authorization") != CLOSED_AUTHORIZATION:
        raise ValueError("measurement authorization widened")
    accounting = measurement.get("accounting") or {}
    if accounting.get("predecessor_road_count") != 140 or accounting.get("extension_highway_way_count") != 591:
        raise ValueError("source accounting drift")
    semantic_basis = dict(measurement)
    actual = semantic_basis.pop("semantic_sha256", None)
    semantic_basis.pop("production_base_sha", None)
    expected = _canonical_sha(semantic_basis)
    if actual != expected:
        raise ValueError(f"semantic SHA mismatch expected={expected} actual={actual}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--predecessor", type=Path, required=True)
    parser.add_argument("--extension-raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        contract = _load(args.contract)
        measurement = build_measurement(contract, args.predecessor.read_bytes(), args.extension_raw.read_bytes())
        validate_measurement(measurement)
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"OSM_ROAD_EXTENSION_RECONCILIATION_RED: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(measurement, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    a = measurement["accounting"]
    f = measurement["frame_comparison"]
    print(
        "OSM_ROAD_EXTENSION_RECONCILIATION_OK "
        f"duplicates={a['duplicate_osm_way_count']} extension_only={a['extension_only_way_count']} "
        f"predecessor_only={a['predecessor_only_way_count']} origin_delta_m={f['origin_delta_magnitude_m']} "
        f"semantic_sha256={measurement['semantic_sha256']} source_merge_authorized=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
