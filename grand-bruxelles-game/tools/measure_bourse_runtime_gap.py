#!/usr/bin/env python3
"""Measure source-backed Bourse street-context alignment without mutating runtime geometry."""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
PROBE_PATH = ROOT / "tools" / "probe_bourse_urbis_context.py"
_spec = importlib.util.spec_from_file_location("bourse_probe", PROBE_PATH)
probe = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(probe)

CITY_PATH = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
HERO_PATH = ROOT / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
TARGET_STREET = "Place de la Bourse"


def point_segment_distance(point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]) -> float:
    px, py = point
    ax, ay = start
    bx, by = end
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq <= 1e-12:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
    qx, qy = ax + t * dx, ay + t * dy
    return math.hypot(px - qx, py - qy)


def distance_to_segments(point: tuple[float, float], segments: list[tuple[tuple[float, float], tuple[float, float]]]) -> float:
    if not segments:
        return math.inf
    return min(point_segment_distance(point, start, end) for start, end in segments)


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = max(0.0, min(1.0, q)) * (len(ordered) - 1)
    low = int(math.floor(position))
    high = int(math.ceil(position))
    if low == high:
        return ordered[low]
    weight = position - low
    return ordered[low] * (1.0 - weight) + ordered[high] * weight


def load_world_transform() -> dict[str, Any]:
    hero = json.loads(HERO_PATH.read_text(encoding="utf-8"))
    transform = hero["transform"]
    return {
        "lambert72_origin": [float(transform["lambert72_origin"][0]), float(transform["lambert72_origin"][1])],
        "world_origin": [float(transform["world_origin"][0]), float(transform["world_origin"][2])],
        "source": str(HERO_PATH.relative_to(ROOT)),
    }


def lambert_to_world(point: tuple[float, float], transform: dict[str, Any]) -> tuple[float, float]:
    east, north = point
    source_e, source_n = transform["lambert72_origin"]
    world_x, world_z = transform["world_origin"]
    return world_x + (east - source_e), world_z - (north - source_n)


def geometry_points(feature: dict[str, Any]) -> list[tuple[float, float]]:
    geometry = feature.get("geometry", {})
    return list(probe.iter_xy(geometry.get("coordinates"))) if isinstance(geometry, dict) else []


def line_segments(points: list[tuple[float, float]]) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    return [(points[index], points[index + 1]) for index in range(len(points) - 1) if points[index] != points[index + 1]]


def official_target_features(payload: dict[str, Any], street_name: str = TARGET_STREET) -> list[dict[str, Any]]:
    result = []
    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        properties = feature.get("properties", {})
        if isinstance(properties, dict) and str(properties.get("STRNAMEFRE", "")) == street_name:
            result.append(feature)
    return result


def runtime_road_segments(city: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for road in city.get("roads", []):
        if not isinstance(road, dict):
            continue
        points = road.get("points", [])
        converted = [(float(point[0]), float(point[1])) for point in points if isinstance(point, list) and len(point) >= 2]
        for start, end in line_segments(converted):
            result.append({"road": road, "start": start, "end": end})
    return result


def runtime_width(road: dict[str, Any]) -> float:
    width = float(road.get("width", 4.5))
    road_class = str(road.get("class", ""))
    minimum = {"primary": 10.5, "secondary": 8.5, "tertiary": 7.2}.get(road_class)
    return max(width, minimum) if minimum is not None else width


def procedural_outer_half_width(road: dict[str, Any]) -> float:
    road_class = str(road.get("class", ""))
    sidewalk_width = 2.55 if road_class in {"primary", "secondary"} else 1.85
    return runtime_width(road) * 0.5 + sidewalk_width + 0.10


def build_report() -> dict[str, Any]:
    transform = load_world_transform()
    bbox = probe.probe_bbox()
    surfaces_payload, _ = probe.fetch_layer(probe.LAYERS["street_surfaces"], bbox)
    axes_payload, _ = probe.fetch_layer(probe.LAYERS["street_axes"], bbox)
    surfaces = official_target_features(surfaces_payload)
    axes = official_target_features(axes_payload)
    if not surfaces:
        raise RuntimeError("official UrbIS returned no Place de la Bourse StreetSurfaces")
    if not axes:
        raise RuntimeError("official UrbIS returned no Place de la Bourse StreetAxes")

    official_axis_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    official_axis_features: list[dict[str, Any]] = []
    for feature in axes:
        source_points = geometry_points(feature)
        world_points = [lambert_to_world(point, transform) for point in source_points]
        official_axis_segments.extend(line_segments(world_points))
        properties = feature.get("properties", {})
        official_axis_features.append({
            "inspire_id": properties.get("INSPIRE_ID"),
            "type": properties.get("TYPE"),
            "length_m": properties.get("LENGTH"),
            "world_points": world_points,
        })

    surface_vertex_offsets: list[float] = []
    official_surfaces: list[dict[str, Any]] = []
    for feature in surfaces:
        properties = feature.get("properties", {})
        source_points = geometry_points(feature)
        world_points = [lambert_to_world(point, transform) for point in source_points]
        offsets = [distance_to_segments(point, official_axis_segments) for point in world_points]
        surface_vertex_offsets.extend(offsets)
        official_surfaces.append({
            "inspire_id": properties.get("INSPIRE_ID"),
            "type": properties.get("TYPE"),
            "area_m2": properties.get("AREA"),
            "vertex_count": len(world_points),
            "lateral_vertex_p50_m": percentile(offsets, 0.50),
            "lateral_vertex_p95_m": percentile(offsets, 0.95),
            "lateral_vertex_max_m": max(offsets) if offsets else None,
        })

    city = json.loads(CITY_PATH.read_text(encoding="utf-8"))
    runtime_segments = runtime_road_segments(city)
    if not runtime_segments:
        raise RuntimeError("runtime OSM slice contains no road segments")

    axis_vertices = [point for item in official_axis_features for point in item["world_points"]]
    vertex_runtime_errors: list[float] = []
    for point in axis_vertices:
        vertex_runtime_errors.append(min(point_segment_distance(point, segment["start"], segment["end"]) for segment in runtime_segments))

    ranked_runtime_roads: dict[str, dict[str, Any]] = {}
    for segment in runtime_segments:
        road = segment["road"]
        distance = min(point_segment_distance(point, segment["start"], segment["end"]) for point in axis_vertices)
        if distance > 12.0:
            continue
        road_key = str(road.get("osm_id", road.get("name", "unknown")))
        candidate = {
            "osm_id": road.get("osm_id"),
            "name": road.get("name"),
            "class": road.get("class"),
            "source_width_m": road.get("width"),
            "runtime_road_width_m": runtime_width(road),
            "procedural_outer_half_width_m": procedural_outer_half_width(road),
            "nearest_official_axis_vertex_m": distance,
        }
        previous = ranked_runtime_roads.get(road_key)
        if previous is None or distance < float(previous["nearest_official_axis_vertex_m"]):
            ranked_runtime_roads[road_key] = candidate

    nearby_roads = sorted(ranked_runtime_roads.values(), key=lambda item: float(item["nearest_official_axis_vertex_m"]))[:12]
    if not nearby_roads:
        raise RuntimeError("no runtime road segment lies within 12 m of official Place de la Bourse axis vertices")

    runtime_outer_half_max = max(float(item["procedural_outer_half_width_m"]) for item in nearby_roads)
    official_p95 = percentile(surface_vertex_offsets, 0.95)
    return {
        "schema": "grand-bruxelles-bourse-runtime-gap-v1",
        "source_crs": probe.CRS,
        "target_street": TARGET_STREET,
        "transform": transform,
        "official": {
            "street_axis_features": official_axis_features,
            "street_surface_features": official_surfaces,
            "surface_vertex_lateral_p50_m": percentile(surface_vertex_offsets, 0.50),
            "surface_vertex_lateral_p95_m": official_p95,
            "surface_vertex_lateral_max_m": max(surface_vertex_offsets) if surface_vertex_offsets else None,
        },
        "runtime": {
            "axis_vertex_error_p50_m": percentile(vertex_runtime_errors, 0.50),
            "axis_vertex_error_p95_m": percentile(vertex_runtime_errors, 0.95),
            "axis_vertex_error_max_m": max(vertex_runtime_errors),
            "nearby_roads": nearby_roads,
            "procedural_outer_half_width_max_m": runtime_outer_half_max,
        },
        "diagnostic": {
            "official_surface_p95_minus_runtime_outer_half_width_m": (official_p95 - runtime_outer_half_max) if official_p95 is not None else None,
            "interpretation_limit": "Diagnostic envelope only. UrbIS TYPE codes are preserved but not semantically re-labelled; do not interpret this value as curb or carriageway width without a source-backed TYPE definition and section-specific geometry validation.",
        },
        "runtime_approved": False,
        "realism_complete": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = build_report()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
