#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/qa/photo_match/atomium_base_pavilion_footprint_contract.json"
ANCHOR_EVIDENCE_PATH = ROOT / "data/qa/photo_match/atomium_anchor_semantics_evidence.json"


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


def git_blob_sha1(payload: bytes) -> str:
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def ring_without_close(raw: Any) -> list[tuple[float, float]]:
    if not isinstance(raw, list):
        return []
    points: list[tuple[float, float]] = []
    for item in raw:
        if not isinstance(item, list) or len(item) < 2:
            continue
        points.append((float(item[0]), float(item[1])))
    if len(points) >= 2 and math.dist(points[0], points[-1]) <= 1e-9:
        points.pop()
    return points


def ring_signed_area_centroid(points: list[tuple[float, float]]) -> tuple[float, float, float]:
    if len(points) < 3:
        return 0.0, 0.0, 0.0
    cross_sum = 0.0
    cx_sum = 0.0
    cy_sum = 0.0
    for i, (x0, y0) in enumerate(points):
        x1, y1 = points[(i + 1) % len(points)]
        cross = x0 * y1 - x1 * y0
        cross_sum += cross
        cx_sum += (x0 + x1) * cross
        cy_sum += (y0 + y1) * cross
    signed_area = cross_sum * 0.5
    if abs(signed_area) <= 1e-12:
        return 0.0, 0.0, 0.0
    cx = cx_sum / (6.0 * signed_area)
    cy = cy_sum / (6.0 * signed_area)
    return signed_area, cx, cy


def ring_perimeter(points: list[tuple[float, float]]) -> float:
    if len(points) < 2:
        return 0.0
    return sum(math.dist(points[i], points[(i + 1) % len(points)]) for i in range(len(points)))


def iter_polygons(geometry: dict[str, Any]) -> Iterable[list[Any]]:
    kind = str(geometry.get("type", ""))
    coords = geometry.get("coordinates")
    if kind == "Polygon" and isinstance(coords, list):
        yield coords
    elif kind == "MultiPolygon" and isinstance(coords, list):
        for polygon in coords:
            if isinstance(polygon, list):
                yield polygon


def geometry_metrics(geometry: dict[str, Any]) -> dict[str, Any] | None:
    total_area = 0.0
    weighted_x = 0.0
    weighted_y = 0.0
    total_perimeter = 0.0
    all_points: list[tuple[float, float]] = []
    polygon_count = 0

    for polygon in iter_polygons(geometry):
        if not polygon:
            continue
        outer = ring_without_close(polygon[0])
        if len(outer) < 3:
            continue
        polygon_count += 1
        all_points.extend(outer)
        outer_signed, outer_cx, outer_cy = ring_signed_area_centroid(outer)
        outer_area = abs(outer_signed)
        if outer_area <= 1e-9:
            continue
        area = outer_area
        moment_x = outer_cx * outer_area
        moment_y = outer_cy * outer_area
        perimeter = ring_perimeter(outer)

        for raw_hole in polygon[1:]:
            hole = ring_without_close(raw_hole)
            if len(hole) < 3:
                continue
            all_points.extend(hole)
            hole_signed, hole_cx, hole_cy = ring_signed_area_centroid(hole)
            hole_area = abs(hole_signed)
            if hole_area <= 1e-9:
                continue
            area -= hole_area
            moment_x -= hole_cx * hole_area
            moment_y -= hole_cy * hole_area
            perimeter += ring_perimeter(hole)

        if area <= 1e-9:
            continue
        total_area += area
        weighted_x += moment_x
        weighted_y += moment_y
        total_perimeter += perimeter

    if total_area <= 1e-9 or total_perimeter <= 1e-9 or not all_points:
        return None

    cx = weighted_x / total_area
    cy = weighted_y / total_area
    xs = [p[0] for p in all_points]
    ys = [p[1] for p in all_points]
    width = max(xs) - min(xs)
    depth = max(ys) - min(ys)
    min_span = min(width, depth)
    max_span = max(width, depth)
    aspect = max_span / min_span if min_span > 1e-9 else math.inf
    equivalent_diameter = 2.0 * math.sqrt(total_area / math.pi)
    circularity = 4.0 * math.pi * total_area / (total_perimeter * total_perimeter)
    return {
        "polygon_count": polygon_count,
        "area_m2": total_area,
        "perimeter_m": total_perimeter,
        "centroid_source": [cx, cy],
        "bbox_source": [min(xs), min(ys), max(xs), max(ys)],
        "bbox_width_m": width,
        "bbox_depth_m": depth,
        "bbox_max_span_m": max_span,
        "bbox_aspect_ratio": aspect,
        "equivalent_circle_diameter_m": equivalent_diameter,
        "circularity": circularity,
    }


def first_coordinate(features: list[Any]) -> tuple[float, float]:
    def walk(value: Any) -> tuple[float, float] | None:
        if isinstance(value, list):
            if len(value) >= 2 and all(isinstance(v, (int, float)) for v in value[:2]):
                return float(value[0]), float(value[1])
            for child in value:
                found = walk(child)
                if found is not None:
                    return found
        return None

    for feature in features:
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry")
        if not isinstance(geometry, dict):
            continue
        found = walk(geometry.get("coordinates"))
        if found is not None:
            return found
    raise AssertionError("no usable coordinate in source features")


def source_space_for(sample: tuple[float, float]) -> str:
    x, y = sample
    if 100000.0 <= x <= 300000.0 and 100000.0 <= y <= 300000.0:
        return "epsg31370"
    if abs(x) <= 10000.0 and abs(y) <= 20000.0:
        return "game_xz_m"
    raise AssertionError(f"unrecognized source coordinate space from sample {sample}")


def epsg_to_game(e: float, n: float, origin_e: float, origin_n: float) -> tuple[float, float]:
    return e - origin_e, -(n - origin_n)


def source_point_from_epsg(e: float, n: float, space: str, origin_e: float, origin_n: float) -> tuple[float, float]:
    if space == "epsg31370":
        return e, n
    return epsg_to_game(e, n, origin_e, origin_n)


def source_to_epsg(point: list[float], space: str, origin_e: float, origin_n: float) -> list[float]:
    if space == "epsg31370":
        return [float(point[0]), float(point[1])]
    x, z = float(point[0]), float(point[1])
    return [x + origin_e, origin_n - z]


def feature_identity(feature: dict[str, Any], index: int) -> dict[str, Any]:
    props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
    keys = (
        "id", "ID", "fid", "FID", "objectid", "OBJECTID", "OBJECTID_1",
        "inspireId", "INSPIREID", "inspire_id", "INSPIRE_ID", "uri", "URI",
    )
    identity: dict[str, Any] = {"feature_index": index}
    if feature.get("id") is not None:
        identity["feature_id"] = feature.get("id")
    for key in keys:
        if key in props and props[key] not in (None, ""):
            identity[f"property_{key}"] = props[key]
    return identity


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    contract = read_json(CONTRACT_PATH)
    anchor_evidence = read_json(ANCHOR_EVIDENCE_PATH)
    source_bytes = args.source.read_bytes()
    source_blob = git_blob_sha1(source_bytes)
    expected_blob = str(contract["source"]["expected_git_blob_sha1"])
    assert source_blob == expected_blob, f"official BuildingFootprint blob drift: {source_blob} != {expected_blob}"

    source = json.loads(source_bytes.decode("utf-8"))
    assert isinstance(source, dict)
    features = source.get("features")
    assert isinstance(features, list), "official BuildingFootprint slice has no features array"
    expected_count = int(contract["source"]["expected_feature_count"])
    assert len(features) == expected_count, f"feature-count drift: {len(features)} != {expected_count}"

    sample = first_coordinate(features)
    source_space = source_space_for(sample)
    coord = contract["project_coordinate_contract"]
    origin_e = float(coord["origin_e"])
    origin_n = float(coord["origin_n"])
    relation_epsg = [float(v) for v in contract["independent_position_witnesses"]["monument_relation_position_epsg31370"]]
    ticket_epsg = [float(v) for v in contract["independent_position_witnesses"]["production_ticket_reference_epsg31370"]]
    relation_source = source_point_from_epsg(relation_epsg[0], relation_epsg[1], source_space, origin_e, origin_n)
    ticket_source = source_point_from_epsg(ticket_epsg[0], ticket_epsg[1], source_space, origin_e, origin_n)

    filters = contract["frozen_discovery_filters"]
    max_distance = float(filters["max_centroid_distance_from_monument_witness_m"])
    diameter_min, diameter_max = [float(v) for v in filters["equivalent_circle_diameter_m"]]
    max_aspect = float(filters["max_bbox_aspect_ratio"])
    max_span = float(filters["max_bbox_span_m"])
    min_circularity = float(filters["min_circularity_4pi_area_over_perimeter_sq"])

    nearby: list[dict[str, Any]] = []
    candidates: list[dict[str, Any]] = []
    usable_features = 0
    for index, raw_feature in enumerate(features):
        if not isinstance(raw_feature, dict):
            continue
        geometry = raw_feature.get("geometry")
        if not isinstance(geometry, dict):
            continue
        metrics = geometry_metrics(geometry)
        if metrics is None:
            continue
        usable_features += 1
        cx, cy = [float(v) for v in metrics["centroid_source"]]
        relation_distance = math.hypot(cx - relation_source[0], cy - relation_source[1])
        ticket_distance = math.hypot(cx - ticket_source[0], cy - ticket_source[1])
        row: dict[str, Any] = {
            **feature_identity(raw_feature, index),
            **metrics,
            "centroid_epsg31370": source_to_epsg(metrics["centroid_source"], source_space, origin_e, origin_n),
            "distance_to_monument_relation_witness_m": relation_distance,
            "distance_to_ticket_reference_m": ticket_distance,
        }
        if relation_distance <= max_distance:
            nearby.append(row)
            if (
                diameter_min <= float(metrics["equivalent_circle_diameter_m"]) <= diameter_max
                and float(metrics["bbox_aspect_ratio"]) <= max_aspect
                and float(metrics["bbox_max_span_m"]) <= max_span
                and float(metrics["circularity"]) >= min_circularity
            ):
                candidates.append(row)

    nearby.sort(key=lambda row: (float(row["distance_to_monument_relation_witness_m"]), int(row["feature_index"])))
    candidates.sort(key=lambda row: (float(row["distance_to_monument_relation_witness_m"]), int(row["feature_index"])))
    outcome = "no_candidate" if not candidates else "unique_candidate" if len(candidates) == 1 else "ambiguous_candidates"

    report = {
        "schema": "grand-bruxelles-atomium-base-pavilion-footprint-discovery-report-v1",
        "source": {
            "git_blob_sha1": source_blob,
            "bytes": len(source_bytes),
            "feature_count": len(features),
            "usable_geometry_feature_count": usable_features,
            "detected_coordinate_space": source_space,
        },
        "frozen_filters": filters,
        "witnesses": {
            "monument_relation_epsg31370": relation_epsg,
            "monument_relation_source_space": list(relation_source),
            "ticket_reference_epsg31370": ticket_epsg,
            "ticket_reference_source_space": list(ticket_source),
            "anchor_semantics_status": anchor_evidence["status"],
        },
        "nearby_feature_count_within_80m": len(nearby),
        "candidate_count": len(candidates),
        "outcome": outcome,
        "candidates": candidates,
        "nearest_12_features": nearby[:12],
        "status": {
            "replacement_anchor_approved": False,
            "runtime_move_authorized": False,
            "support_pillar_geometry_authorized": False,
            "yaw_authorized": False,
            "realism_complete": False,
        },
        "next_action": (
            "If exactly one candidate exists, register that official footprint against the frozen 2024 orthophoto with explicit uncertainty in a separate evidence lot. "
            "If zero or multiple candidates exist, keep the centre unresolved and do not loosen these filters."
        ),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "ATOMIUM_BASE_PAVILION_DISCOVERY_OK: "
        f"space={source_space} features={len(features)} usable={usable_features} nearby80={len(nearby)} "
        f"candidates={len(candidates)} outcome={outcome} source_blob={source_blob}"
    )
    for rank, row in enumerate(candidates, start=1):
        print(
            "ATOMIUM_BASE_PAVILION_CANDIDATE: "
            f"rank={rank} feature_index={row['feature_index']} "
            f"centroid_epsg={row['centroid_epsg31370']} distance_relation_m={row['distance_to_monument_relation_witness_m']:.3f} "
            f"diameter_eq_m={row['equivalent_circle_diameter_m']:.3f} aspect={row['bbox_aspect_ratio']:.3f} "
            f"span_m={row['bbox_max_span_m']:.3f} circularity={row['circularity']:.3f}"
        )
    print("ATOMIUM_BASE_PAVILION_RUNTIME_REFUSAL_OK: replacement_anchor_approved=false runtime_move_authorized=false support_pillar_geometry_authorized=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
