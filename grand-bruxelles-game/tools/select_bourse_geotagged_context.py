#!/usr/bin/env python3
"""Select official UrbIS buildings that actually intersect the geotagged Bourse view.

This is an evidence selector, not a runtime promoter. It consumes the source-backed
camera witness and an EPSG:31370 UrbIS Buildings FeatureCollection, then ranks
buildings whose geometry falls inside the horizontal camera cone. No geometry is
moved and no missing façade is invented.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable

HERO_BUILDING_ID = "https://databrussels.be/id/building/1751663"


def iter_xy(value: Any) -> Iterable[tuple[float, float]]:
    if not isinstance(value, list):
        return
    if len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
        yield float(value[0]), float(value[1])
        return
    for child in value:
        yield from iter_xy(child)


def normalize_delta_degrees(value: float) -> float:
    return abs((value + 180.0) % 360.0 - 180.0)


def true_bearing_degrees(camera_e: float, camera_n: float, east: float, north: float) -> float:
    return math.degrees(math.atan2(east - camera_e, north - camera_n)) % 360.0


def coordinate_bounds(coords: list[tuple[float, float]]) -> list[float]:
    xs = [p[0] for p in coords]
    ys = [p[1] for p in coords]
    return [min(xs), min(ys), max(xs), max(ys)]


def feature_building_id(feature: dict[str, Any]) -> str:
    properties = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
    inspire_id = str(properties.get("INSPIRE_ID", "")).strip()
    if inspire_id:
        return inspire_id
    raw_id = str(feature.get("id", "")).strip()
    return raw_id


def summarize_feature(
    feature: dict[str, Any],
    camera_e: float,
    camera_n: float,
    heading_degrees: float,
) -> dict[str, Any] | None:
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        return None
    coords = list(iter_xy(geometry.get("coordinates")))
    if not coords:
        return None

    center_e = sum(p[0] for p in coords) / len(coords)
    center_n = sum(p[1] for p in coords) / len(coords)
    center_bearing = true_bearing_degrees(camera_e, camera_n, center_e, center_n)
    center_delta = normalize_delta_degrees(center_bearing - heading_degrees)

    nearest_distance = min(math.hypot(e - camera_e, n - camera_n) for e, n in coords)
    angular_deltas = [
        normalize_delta_degrees(true_bearing_degrees(camera_e, camera_n, e, n) - heading_degrees)
        for e, n in coords
    ]
    angular_deltas.append(center_delta)

    properties = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
    return {
        "building_id": feature_building_id(feature),
        "wfs_feature_id": feature.get("id"),
        "geometry_type": geometry.get("type"),
        "coordinate_bounds_epsg31370": coordinate_bounds(coords),
        "coordinate_count": len(coords),
        "nearest_camera_distance_m": nearest_distance,
        "center_epsg31370": [center_e, center_n],
        "center_true_bearing_degrees": center_bearing,
        "center_heading_delta_degrees": center_delta,
        "minimum_geometry_heading_delta_degrees": min(angular_deltas),
        "source_type": properties.get("TYPE"),
    }


def select_candidates(
    buildings: dict[str, Any],
    camera_e: float,
    camera_n: float,
    heading_degrees: float,
    horizontal_fov_degrees: float,
    max_distance_m: float,
    margin_degrees: float,
    limit: int,
) -> list[dict[str, Any]]:
    if buildings.get("type") != "FeatureCollection":
        raise ValueError("buildings input must be a FeatureCollection")
    half_fov = horizontal_fov_degrees * 0.5
    candidates: list[dict[str, Any]] = []
    for feature in buildings.get("features", []):
        if not isinstance(feature, dict):
            continue
        summary = summarize_feature(feature, camera_e, camera_n, heading_degrees)
        if summary is None:
            continue
        if summary["building_id"] == HERO_BUILDING_ID:
            continue
        if not summary["building_id"]:
            continue
        if float(summary["nearest_camera_distance_m"]) > max_distance_m:
            continue
        if float(summary["minimum_geometry_heading_delta_degrees"]) > half_fov + margin_degrees:
            continue
        candidates.append(summary)

    candidates.sort(
        key=lambda row: (
            float(row["minimum_geometry_heading_delta_degrees"]),
            float(row["nearest_camera_distance_m"]),
            str(row["building_id"]),
        )
    )
    return candidates[: max(1, limit)]


def build_report(
    buildings: dict[str, Any],
    camera_evidence: dict[str, Any],
    max_distance_m: float,
    margin_degrees: float,
    limit: int,
) -> dict[str, Any]:
    reference = camera_evidence["reference"]
    transform = camera_evidence["project_transform"]
    optics = camera_evidence["optics"]
    camera_e, camera_n = [float(v) for v in transform["lambert72_camera_e_n_m"]]
    heading = float(reference["image_direction_true_degrees"])
    horizontal_fov = float(optics["horizontal_fov_from_35mm_equivalent_degrees"])
    candidates = select_candidates(
        buildings,
        camera_e,
        camera_n,
        heading,
        horizontal_fov,
        max_distance_m,
        margin_degrees,
        limit,
    )
    return {
        "schema": "grand-bruxelles-bourse-geotagged-context-selection-v1",
        "source_crs": "EPSG:31370",
        "camera_evidence_schema": camera_evidence["schema"],
        "camera_e_n": [camera_e, camera_n],
        "published_true_heading_degrees": heading,
        "horizontal_fov_degrees": horizontal_fov,
        "selection_half_fov_degrees": horizontal_fov * 0.5,
        "selection_margin_degrees": margin_degrees,
        "max_camera_distance_m": max_distance_m,
        "hero_building_excluded": HERO_BUILDING_ID,
        "wfs_feature_count": len(buildings.get("features", [])),
        "candidate_count": len(candidates),
        "candidates": candidates,
        "runtime_approved": False,
        "realism_complete": False,
        "status": "official_2d_camera_frustum_candidates_only_pending_urbis3d_resolution",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--camera-evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-distance-m", type=float, default=180.0)
    parser.add_argument("--margin-degrees", type=float, default=3.0)
    parser.add_argument("--limit", type=int, default=12)
    args = parser.parse_args()

    buildings = json.loads(args.buildings.read_text(encoding="utf-8"))
    evidence = json.loads(args.camera_evidence.read_text(encoding="utf-8"))
    report = build_report(
        buildings,
        evidence,
        args.max_distance_m,
        args.margin_degrees,
        args.limit,
    )
    if not report["candidates"]:
        raise SystemExit("no official buildings intersect the geotagged camera cone")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
