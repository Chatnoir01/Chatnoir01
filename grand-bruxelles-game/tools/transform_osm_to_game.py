#!/usr/bin/env python3
"""Convert an Overpass JSON extract into lightweight Grand Bruxelles game data.

The converter projects latitude/longitude into local metric coordinates, keeps
road centerlines, and turns closed OSM building ways into simple footprints.
Supported point furniture is preserved only when its OSM semantics are explicit.
This is a greybox pipeline: landmark modelling and facade work remain separate.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_378_137.0
DEFAULT_ORIGIN = (50.8419, 4.3480)

ROAD_WIDTHS = {
    "motorway": 12.0,
    "trunk": 11.0,
    "primary": 9.0,
    "secondary": 8.0,
    "tertiary": 7.0,
    "unclassified": 6.0,
    "residential": 5.6,
    "living_street": 5.0,
    "service": 4.0,
    "pedestrian": 4.0,
    "track": 3.2,
    "cycleway": 2.2,
    "footway": 1.8,
    "path": 1.6,
}

DRIVABLE = {
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "unclassified", "residential", "living_street", "service",
}


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_non_standard_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _parse_finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON float: {value}")
    return parsed


def load_strict_overpass_json(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    try:
        value = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_non_standard_constant,
            parse_float=_parse_finite_float,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Overpass source is not strict UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise ValueError("Overpass source must be a JSON object")
    if not isinstance(value.get("elements"), list):
        raise ValueError("Overpass source elements must be a JSON array")
    return value


def metric_point(lat: float, lon: float, origin_lat: float, origin_lon: float) -> list[float]:
    """Project WGS84 approximately to a local tangent plane in metres.

    Godot convention used here: +X east, -Z north.
    """
    for label, value in (("lat", lat), ("lon", lon), ("origin_lat", origin_lat), ("origin_lon", origin_lon)):
        if not math.isfinite(value):
            raise ValueError(f"{label} must be finite")
    lat0 = math.radians(origin_lat)
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    return [round(x, 3), round(-north, 3)]


def numeric_tag(tags: dict[str, Any], key: str) -> float | None:
    raw = tags.get(key)
    if raw is None:
        return None
    try:
        text = str(raw).strip().lower().replace("m", "").strip()
        parsed = float(text)
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) else None


def truthy_osm_tag(tags: dict[str, Any], key: str) -> bool:
    raw = tags.get(key)
    if raw is None:
        return False
    return str(raw).strip().lower() not in {"", "0", "false", "no", "none"}


def railway_vertical_metadata(tags: dict[str, Any]) -> dict[str, Any]:
    tunnel = truthy_osm_tag(tags, "tunnel")
    covered = truthy_osm_tag(tags, "covered")
    raw_layer = numeric_tag(tags, "layer")
    layer = 0.0 if raw_layer is None else raw_layer
    return {
        "tunnel": tunnel,
        "covered": covered,
        "layer": layer,
        "surface_visible": not tunnel and not covered and layer >= 0.0,
    }


def building_height(tags: dict[str, Any]) -> float:
    direct = numeric_tag(tags, "height")
    if direct and 2.0 <= direct <= 250.0:
        return round(direct, 2)

    levels = numeric_tag(tags, "building:levels")
    if levels and 1.0 <= levels <= 80.0:
        return round(max(3.2, levels * 3.15), 2)

    kind = str(tags.get("building", "yes"))
    defaults = {
        "house": 8.5,
        "apartments": 14.0,
        "commercial": 12.0,
        "retail": 9.5,
        "office": 15.0,
        "church": 18.0,
        "cathedral": 28.0,
        "train_station": 15.0,
        "garage": 3.5,
        "garages": 3.5,
        "shed": 3.0,
    }
    return defaults.get(kind, 10.5)


def geometry_points(element: dict[str, Any], origin: tuple[float, float]) -> list[list[float]]:
    out: list[list[float]] = []
    for point in element.get("geometry", []) or []:
        if not isinstance(point, dict) or "lat" not in point or "lon" not in point:
            continue
        projected = metric_point(float(point["lat"]), float(point["lon"]), *origin)
        if not out or projected != out[-1]:
            out.append(projected)
    return out


def environment_point_kind(tags: dict[str, Any]) -> str | None:
    if tags.get("natural") == "tree":
        return "tree"
    if tags.get("highway") == "street_lamp":
        return "street_lamp"
    if tags.get("barrier") == "bollard":
        return "bollard"
    return None


def polygon_area(points: list[list[float]]) -> float:
    if len(points) < 3:
        return 0.0
    total = 0.0
    for idx, point in enumerate(points):
        nxt = points[(idx + 1) % len(points)]
        total += point[0] * nxt[1] - nxt[0] * point[1]
    return abs(total) * 0.5


def convert(data: dict[str, Any], origin: tuple[float, float]) -> dict[str, Any]:
    roads: list[dict[str, Any]] = []
    buildings: list[dict[str, Any]] = []
    railways: list[dict[str, Any]] = []
    environment_points: list[dict[str, Any]] = []

    elements = data.get("elements")
    if not isinstance(elements, list):
        raise ValueError("Overpass source elements must be a JSON array")

    for element in elements:
        if not isinstance(element, dict):
            raise ValueError("Overpass elements must be JSON objects")
        tags = element.get("tags", {}) or {}
        if not isinstance(tags, dict):
            raise ValueError("OSM element tags must be a JSON object")
        if element.get("type") == "node":
            kind = environment_point_kind(tags)
            if kind and "lat" in element and "lon" in element:
                environment_points.append({
                    "osm_id": element.get("id"),
                    "kind": kind,
                    "position": metric_point(float(element["lat"]), float(element["lon"]), *origin),
                })
            continue
        if element.get("type") != "way":
            continue

        points = geometry_points(element, origin)
        if len(points) < 2:
            continue

        highway = tags.get("highway")
        if highway:
            width = ROAD_WIDTHS.get(str(highway), 4.5)
            lanes = numeric_tag(tags, "lanes")
            if lanes and lanes >= 2:
                width = max(width, lanes * 3.0)
            roads.append({
                "osm_id": element.get("id"),
                "name": tags.get("name", ""),
                "class": highway,
                "width": round(width, 2),
                "drivable": highway in DRIVABLE,
                "points": points,
            })

        railway = tags.get("railway")
        if railway:
            railways.append({
                "osm_id": element.get("id"),
                "name": tags.get("name", ""),
                "class": railway,
                **railway_vertical_metadata(tags),
                "points": points,
            })

        if "building" in tags and len(points) >= 4:
            if points[0] == points[-1]:
                points = points[:-1]
            area = polygon_area(points)
            if len(points) >= 3 and 8.0 <= area <= 60_000.0:
                buildings.append({
                    "osm_id": element.get("id"),
                    "name": tags.get("name", ""),
                    "kind": tags.get("building", "yes"),
                    "height": building_height(tags),
                    "area": round(area, 2),
                    "footprint": points,
                })

    bounds = [0.0, 0.0, 0.0, 0.0]
    all_points = [p for road in roads for p in road["points"]]
    all_points += [p for b in buildings for p in b["footprint"]]
    all_points += [p["position"] for p in environment_points]
    if all_points:
        xs = [p[0] for p in all_points]
        zs = [p[1] for p in all_points]
        bounds = [round(min(xs), 2), round(min(zs), 2), round(max(xs), 2), round(max(zs), 2)]

    roads.sort(key=lambda r: (not r["drivable"], str(r["class"]), int(r["osm_id"] or 0)))
    buildings.sort(key=lambda b: (-float(b["area"]), int(b["osm_id"] or 0)))
    environment_points.sort(key=lambda p: (str(p["kind"]), int(p["osm_id"] or 0)))

    return {
        "format": "grand-bruxelles-osm-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "origin": {"lat": origin[0], "lon": origin[1]},
        "bounds_m": bounds,
        "stats": {
            "roads": len(roads),
            "drivable_roads": sum(1 for road in roads if road["drivable"]),
            "buildings": len(buildings),
            "railways": len(railways),
            "environment_points": len(environment_points),
        },
        "roads": roads,
        "buildings": buildings,
        "railways": railways,
        "environment_points": environment_points,
    }


def parse_origin(raw: str) -> tuple[float, float]:
    try:
        parts = [float(part.strip()) for part in raw.split(",")]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("origin must be finite lat,lon") from exc
    if len(parts) != 2 or not all(math.isfinite(value) for value in parts):
        raise argparse.ArgumentTypeError("origin must be finite lat,lon")
    return parts[0], parts[1]


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Overpass JSON into Grand Bruxelles game data")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--origin", type=parse_origin, default=DEFAULT_ORIGIN)
    args = parser.parse_args()

    try:
        raw = load_strict_overpass_json(args.input)
        converted = convert(raw, args.origin)
        serialized = json.dumps(converted, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    except (OSError, TypeError, ValueError) as exc:
        print(f"transform_osm_to_game: {exc}", file=sys.stderr)
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(serialized, encoding="utf-8")

    stats = converted["stats"]
    print(
        "converted "
        f"{stats['roads']} roads / {stats['buildings']} buildings / "
        f"{stats['railways']} railways / {stats['environment_points']} environment points -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
