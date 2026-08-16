#!/usr/bin/env python3
"""Create a compact playable OSM ribbon for Grand Bruxelles.

The full Overpass extract is intentionally broader than what the prototype
should instantiate at once. This tool keeps a corridor around the vertical
slice control points (Midi -> Anneessens -> Bourse -> Grand-Place) and writes a
small deterministic JSON file suitable for committing to the repository.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_378_137.0
ROAD_PRIORITY = {
    "primary": 0,
    "secondary": 1,
    "tertiary": 2,
    "residential": 3,
    "living_street": 4,
    "service": 5,
    "unclassified": 6,
    "pedestrian": 7,
    "cycleway": 8,
    "footway": 9,
    "path": 10,
}


def project(lat: float, lon: float, origin_lat: float, origin_lon: float) -> tuple[float, float]:
    lat0 = math.radians(origin_lat)
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    return x, -north


def point_segment_distance(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> float:
    px, pz = point
    ax, az = start
    bx, bz = end
    dx = bx - ax
    dz = bz - az
    denominator = dx * dx + dz * dz
    if denominator <= 1e-9:
        return math.hypot(px - ax, pz - az)
    t = ((px - ax) * dx + (pz - az) * dz) / denominator
    t = max(0.0, min(1.0, t))
    qx = ax + t * dx
    qz = az + t * dz
    return math.hypot(px - qx, pz - qz)


def corridor_distance(point: tuple[float, float], anchors: list[tuple[float, float]]) -> float:
    return min(
        point_segment_distance(point, anchors[index], anchors[index + 1])
        for index in range(len(anchors) - 1)
    )


def min_feature_distance(points: list[list[float]], anchors: list[tuple[float, float]]) -> float:
    return min(corridor_distance((float(p[0]), float(p[1])), anchors) for p in points)


def selected_bounds(features: list[dict[str, Any]]) -> list[float]:
    points: list[list[float]] = []
    for feature in features:
        points.extend(feature.get("points", []))
        points.extend(feature.get("footprint", []))
        position = feature.get("position")
        if isinstance(position, list) and len(position) >= 2:
            points.append(position)
    if not points:
        return [0.0, 0.0, 0.0, 0.0]
    xs = [float(p[0]) for p in points]
    zs = [float(p[1]) for p in points]
    return [round(min(xs), 2), round(min(zs), 2), round(max(xs), 2), round(max(zs), 2)]


def select_environment_points(
    source_points: list[dict[str, Any]],
    anchors: list[tuple[float, float]],
    radius: float,
    max_points: int,
) -> list[dict[str, Any]]:
    """Keep only explicit source points close to the playable corridor."""
    candidates: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    for point in source_points:
        position = point.get("position")
        if not isinstance(position, list) or len(position) < 2:
            continue
        kind = str(point.get("kind", ""))
        if kind not in {"tree", "street_lamp", "bollard"}:
            continue
        distance = corridor_distance((float(position[0]), float(position[1])), anchors)
        if distance <= radius:
            candidates.append(((round(distance, 4), kind, int(point.get("osm_id") or 0)), point))
    candidates.sort(key=lambda item: item[0])
    return [item[1] for item in candidates[:max_points]]


def select_buildings(
    source_buildings: list[dict[str, Any]],
    anchors: list[tuple[float, float]],
    building_radius: float,
    max_buildings: int,
    required_osm_ids: list[int],
) -> list[dict[str, Any]]:
    """Select a compact corridor set without dropping declared hero buildings."""
    candidates: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    for building in source_buildings:
        footprint = building.get("footprint", [])
        if not footprint:
            continue
        center = (
            sum(float(point[0]) for point in footprint) / len(footprint),
            sum(float(point[1]) for point in footprint) / len(footprint),
        )
        distance = corridor_distance(center, anchors)
        if distance <= building_radius:
            key = (
                round(distance, 4),
                -float(building.get("area", 0.0)),
                int(building.get("osm_id") or 0),
            )
            candidates.append((key, building))
    candidates.sort(key=lambda item: item[0])

    required_ids = list(dict.fromkeys(int(osm_id) for osm_id in required_osm_ids))
    if len(required_ids) > max_buildings:
        raise ValueError(
            f"{len(required_ids)} required hero buildings exceed max-buildings={max_buildings}"
        )

    candidates_by_id = {
        int(building.get("osm_id") or 0): (key, building)
        for key, building in candidates
    }
    missing = [osm_id for osm_id in required_ids if osm_id not in candidates_by_id]
    if missing:
        raise ValueError(
            "required OSM hero buildings are absent from the source/corridor: "
            + ", ".join(str(osm_id) for osm_id in missing)
        )

    required_set = set(required_ids)
    selected = [candidates_by_id[osm_id] for osm_id in required_ids]
    selected.extend(
        item for item in candidates
        if int(item[1].get("osm_id") or 0) not in required_set
    )
    selected = selected[:max_buildings]
    selected.sort(key=lambda item: item[0])
    return [item[1] for item in selected]


def required_hero_building_ids(controls: dict[str, Any]) -> list[int]:
    ids: list[int] = []
    for record in controls.get("required_buildings", []):
        if not isinstance(record, dict) or "osm_id" not in record:
            raise ValueError("required_buildings entries must contain osm_id")
        ids.append(int(record["osm_id"]))
    return list(dict.fromkeys(ids))


def main() -> int:
    parser = argparse.ArgumentParser(description="Make compact Midi-to-Grand-Place runtime OSM slice")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--control-points", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--road-radius", type=float, default=170.0)
    parser.add_argument("--building-radius", type=float, default=130.0)
    parser.add_argument("--rail-radius", type=float, default=180.0)
    parser.add_argument("--environment-radius", type=float, default=130.0)
    parser.add_argument("--max-roads", type=int, default=140)
    parser.add_argument("--max-buildings", type=int, default=140)
    parser.add_argument("--max-railways", type=int, default=30)
    parser.add_argument("--max-environment-points", type=int, default=1000)
    args = parser.parse_args()

    full = json.loads(args.input.read_text(encoding="utf-8"))
    controls = json.loads(args.control_points.read_text(encoding="utf-8"))
    origin_lat = float(full["origin"]["lat"])
    origin_lon = float(full["origin"]["lon"])

    anchor_records: list[dict[str, Any]] = []
    anchors: list[tuple[float, float]] = []
    for item in controls.get("points", []):
        x, z = project(float(item["lat"]), float(item["lon"]), origin_lat, origin_lon)
        anchors.append((x, z))
        anchor_records.append({
            "id": item["id"],
            "name": item["name"],
            "x": round(x, 2),
            "z": round(z, 2),
        })

    if len(anchors) < 2:
        raise SystemExit("need at least two corridor control points")

    road_candidates: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    for road in full.get("roads", []):
        points = road.get("points", [])
        if not points:
            continue
        distance = min_feature_distance(points, anchors)
        if distance <= args.road_radius:
            key = (
                0 if bool(road.get("drivable")) else 1,
                ROAD_PRIORITY.get(str(road.get("class", "")), 50),
                round(distance, 4),
                int(road.get("osm_id") or 0),
            )
            road_candidates.append((key, road))
    road_candidates.sort(key=lambda item: item[0])
    roads = [item[1] for item in road_candidates[: args.max_roads]]

    try:
        required_building_ids = required_hero_building_ids(controls)
        buildings = select_buildings(
            full.get("buildings", []),
            anchors,
            args.building_radius,
            args.max_buildings,
            required_building_ids,
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error

    rail_candidates: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    for railway in full.get("railways", []):
        points = railway.get("points", [])
        if not points:
            continue
        distance = min_feature_distance(points, anchors)
        if distance <= args.rail_radius:
            rail_candidates.append(((round(distance, 4), int(railway.get("osm_id") or 0)), railway))
    rail_candidates.sort(key=lambda item: item[0])
    railways = [item[1] for item in rail_candidates[: args.max_railways]]

    environment_points = select_environment_points(
        full.get("environment_points", []),
        anchors,
        args.environment_radius,
        args.max_environment_points,
    )

    subset: dict[str, Any] = {
        "format": full.get("format", "grand-bruxelles-osm-v1"),
        "source": full.get("source", "OpenStreetMap contributors via Overpass API"),
        "license": full.get("license", "ODbL-1.0"),
        "origin": full["origin"],
        "corridor": {
            "name": "Midi -> Anneessens -> Bourse -> Grand-Place",
            "anchors": anchor_records,
            "required_buildings": controls.get("required_buildings", []),
            "selection_radius_m": {
                "roads": args.road_radius,
                "buildings": args.building_radius,
                "railways": args.rail_radius,
                "environment_points": args.environment_radius,
            },
        },
        "source_stats": full.get("stats", {}),
        "stats": {
            "roads": len(roads),
            "drivable_roads": sum(1 for road in roads if road.get("drivable")),
            "buildings": len(buildings),
            "railways": len(railways),
            "environment_points": len(environment_points),
        },
        "roads": roads,
        "buildings": buildings,
        "railways": railways,
        "environment_points": environment_points,
    }
    subset["bounds_m"] = selected_bounds(roads + buildings + railways + environment_points)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(subset, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print("runtime slice stats:", subset["stats"])
    print("runtime bounds (m):", subset["bounds_m"])
    print("runtime bytes:", args.output.stat().st_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
