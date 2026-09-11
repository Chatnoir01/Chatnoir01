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
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_378_137.0
DEFAULT_ORIGIN = (50.8419, 4.3480)
OSM_ELEMENT_TYPES = {"node", "way", "relation"}

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


def _reject_duplicate_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> object:
    raise ValueError(f"non-standard JSON constant: {value}")


def _parse_finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"non-finite JSON float: {value}")
    return number


def _validate_osm_identity(element: dict[str, Any], index: int) -> tuple[str, int]:
    element_type = element.get("type")
    if element_type not in OSM_ELEMENT_TYPES:
        raise ValueError(f"Overpass element {index} has invalid type: {element_type!r}")

    osm_id = element.get("id")
    if isinstance(osm_id, bool) or not isinstance(osm_id, int) or osm_id <= 0:
        raise ValueError(f"Overpass element {index} id must be a positive integer")
    return str(element_type), osm_id


def _finite_coordinate(value: object, label: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{label} must be numeric, not boolean")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be numeric") from exc
    if not math.isfinite(number):
        raise ValueError(f"{label} must be finite")
    return number


def _wgs84_coordinate(value: object, label: str, *, latitude: bool) -> float:
    number = _finite_coordinate(value, label)
    lower, upper = (-90.0, 90.0) if latitude else (-180.0, 180.0)
    if not lower <= number <= upper:
        axis = "latitude" if latitude else "longitude"
        raise ValueError(f"{label} must be within WGS84 {axis} range [{lower:g}, {upper:g}]")
    return number


def load_source_json(path: Path) -> dict[str, Any]:
    """Load a locked Overpass artifact without accepting ambiguous JSON semantics."""
    raw_bytes = path.read_bytes()
    text = raw_bytes.decode("utf-8", errors="strict")
    payload = json.loads(
        text,
        object_pairs_hook=_reject_duplicate_pairs,
        parse_constant=_reject_json_constant,
        parse_float=_parse_finite_float,
    )
    if not isinstance(payload, dict):
        raise ValueError("Overpass source JSON root must be an object")
    elements = payload.get("elements")
    if not isinstance(elements, list):
        raise ValueError("Overpass source JSON elements must be a list")

    seen_identities: set[tuple[str, int]] = set()
    for index, element in enumerate(elements):
        if not isinstance(element, dict):
            raise ValueError(f"Overpass element {index} must be an object")
        identity = _validate_osm_identity(element, index)
        if identity in seen_identities:
            raise ValueError(f"duplicate OSM element identity: {identity[0]}/{identity[1]}")
        seen_identities.add(identity)

        if identity[0] == "node":
            if "lat" not in element or "lon" not in element:
                raise ValueError(f"Overpass node {identity[1]} must contain both lat and lon")
            _wgs84_coordinate(element["lat"], f"Overpass node {identity[1]} latitude", latitude=True)
            _wgs84_coordinate(element["lon"], f"Overpass node {identity[1]} longitude", latitude=False)

        tags = element.get("tags")
        if tags is not None:
            if not isinstance(tags, dict):
                raise ValueError(f"Overpass element {index} tags must be an object")
            for tag_key, tag_value in tags.items():
                if not isinstance(tag_key, str) or not isinstance(tag_value, str):
                    raise ValueError(
                        f"Overpass element {index} tags must map strings to strings; invalid tag {tag_key!r}"
                    )
        geometry = element.get("geometry")
        if geometry is not None:
            if not isinstance(geometry, list):
                raise ValueError(f"Overpass element {index} geometry must be a list")
            for point_index, point in enumerate(geometry):
                if not isinstance(point, dict):
                    raise ValueError(f"Overpass element {index} geometry point {point_index} must be an object")
                if "lat" not in point or "lon" not in point:
                    raise ValueError(
                        f"Overpass element {index} geometry point {point_index} must contain both lat and lon"
                    )
                _wgs84_coordinate(
                    point["lat"],
                    f"Overpass element {index} geometry point {point_index} latitude",
                    latitude=True,
                )
                _wgs84_coordinate(
                    point["lon"],
                    f"Overpass element {index} geometry point {point_index} longitude",
                    latitude=False,
                )
    return payload


def metric_point(lat: float, lon: float, origin_lat: float, origin_lon: float) -> list[float]:
    """Project WGS84 approximately to a local tangent plane in metres.

    Godot convention used here: +X east, -Z north.
    """
    lat = _wgs84_coordinate(lat, "latitude", latitude=True)
    lon = _wgs84_coordinate(lon, "longitude", latitude=False)
    origin_lat = _wgs84_coordinate(origin_lat, "origin latitude", latitude=True)
    origin_lon = _wgs84_coordinate(origin_lon, "origin longitude", latitude=False)
    lat0 = math.radians(origin_lat)
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    if not math.isfinite(x) or not math.isfinite(north):
        raise ValueError("projected coordinate must be finite")
    return [round(x, 3), round(-north, 3)]


def numeric_tag(tags: dict[str, Any], key: str, *, allow_meters: bool = False) -> float | None:
    """Parse an OSM numeric tag without silently stripping arbitrary units."""
    raw = tags.get(key)
    if raw is None or not isinstance(raw, str):
        return None
    text = raw.strip().lower()
    if allow_meters and text.endswith("m"):
        text = text[:-1].rstrip()
    try:
        number = float(text)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


def truthy_osm_tag(tags: dict[str, Any], key: str) -> bool:
    raw = tags.get(key)
    if raw is None:
        return False
    return str(raw).strip().lower() not in {"", "0", "false", "no", "none"}


def railway_vertical_metadata(tags: dict[str, Any]) -> dict[str, Any]:
    tunnel = truthy_osm_tag(tags, "tunnel")
    covered = truthy_osm_tag(tags, "covered")
    raw_layer = numeric_tag(tags, "layer")
    if "layer" in tags and raw_layer is None:
        raise ValueError(f"railway layer must be a finite unitless number: {tags.get('layer')!r}")
    layer = 0.0 if raw_layer is None else raw_layer
    return {
        "tunnel": tunnel,
        "covered": covered,
        "layer": layer,
        "surface_visible": not tunnel and not covered and layer >= 0.0,
    }


def building_height(tags: dict[str, Any]) -> float:
    direct = numeric_tag(tags, "height", allow_meters=True)
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
    geometry = element.get("geometry", []) or []
    if not isinstance(geometry, list):
        raise ValueError("OSM geometry must be a list")
    for point in geometry:
        if not isinstance(point, dict):
            raise ValueError("OSM geometry point must be an object")
        if "lat" not in point or "lon" not in point:
            raise ValueError("OSM geometry point must contain both lat and lon")
        projected = metric_point(point["lat"], point["lon"], *origin)
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
    area = abs(total) * 0.5
    if not math.isfinite(area):
        raise ValueError("polygon area must be finite")
    return area


def convert(data: dict[str, Any], origin: tuple[float, float]) -> dict[str, Any]:
    roads: list[dict[str, Any]] = []
    buildings: list[dict[str, Any]] = []
    railways: list[dict[str, Any]] = []
    environment_points: list[dict[str, Any]] = []

    elements = data.get("elements", [])
    if not isinstance(elements, list):
        raise ValueError("OSM elements must be a list")
    for element in elements:
        if not isinstance(element, dict):
            raise ValueError("OSM element must be an object")
        tags = element.get("tags", {}) or {}
        if not isinstance(tags, dict):
            raise ValueError("OSM tags must be an object")
        if element.get("type") == "node":
            kind = environment_point_kind(tags)
            if kind:
                environment_points.append({
                    "osm_id": element.get("id"),
                    "kind": kind,
                    "position": metric_point(element["lat"], element["lon"], *origin),
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
    all_points += [p for railway in railways for p in railway["points"]]
    all_points += [p["position"] for p in environment_points]
    if all_points:
        xs = [p[0] for p in all_points]
        zs = [p[1] for p in all_points]
        bounds = [round(min(xs), 2), round(min(zs), 2), round(max(xs), 2), round(max(zs), 2)]

    roads.sort(key=lambda r: (not r["drivable"], str(r["class"]), int(r["osm_id"] or 0)))
    buildings.sort(key=lambda b: (-float(b["area"]), int(b["osm_id"] or 0)))
    railways.sort(key=lambda r: (str(r["class"]), int(r["osm_id"] or 0)))
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
        raise argparse.ArgumentTypeError("origin must be lat,lon") from exc
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("origin must be lat,lon")
    try:
        latitude = _wgs84_coordinate(parts[0], "origin latitude", latitude=True)
        longitude = _wgs84_coordinate(parts[1], "origin longitude", latitude=False)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
    return latitude, longitude


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Overpass JSON into Grand Bruxelles game data")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--origin", type=parse_origin, default=DEFAULT_ORIGIN)
    args = parser.parse_args()

    raw = load_source_json(args.input)
    converted = convert(raw, args.origin)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(converted, ensure_ascii=False, separators=(",", ":"), allow_nan=False),
        encoding="utf-8",
    )

    stats = converted["stats"]
    print(
        "converted "
        f"{stats['roads']} roads / {stats['buildings']} buildings / "
        f"{stats['railways']} railways / {stats['environment_points']} environment points -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
