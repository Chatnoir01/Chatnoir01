#!/usr/bin/env python3
"""Convert a STIB-MIVB GTFS ZIP into lightweight Grand Bruxelles runtime data.

Only surface modes used by the road/traffic session are retained: tram (0) and
bus (3). Geometry is projected to the same local metric frame as OSM.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable

EARTH_RADIUS_M = 6_378_137.0
DEFAULT_ORIGIN = (50.8419, 4.3480)
SURFACE_ROUTE_TYPES = {0: "tram", 3: "bus"}
DEFAULT_ANCHORS = [
    (-668.5, 627.84),
    (-272.04, -217.07),
    (81.54, -664.58),
    (319.01, -535.2),
]


def metric_point(lat: float, lon: float, origin_lat: float, origin_lon: float) -> list[float]:
    lat0 = math.radians(origin_lat)
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    return [round(x, 3), round(-north, 3)]


def read_csv(zf: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    with zf.open(name) as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
        return list(csv.DictReader(text))


def segment_distance(point: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    px, pz = point
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    length2 = dx * dx + dz * dz
    if length2 <= 1e-9:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length2))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def corridor_distance(point: tuple[float, float], anchors: Iterable[tuple[float, float]]) -> float:
    anchors = list(anchors)
    if len(anchors) == 1:
        return math.dist(point, anchors[0])
    return min(segment_distance(point, anchors[i], anchors[i + 1]) for i in range(len(anchors) - 1))


def convert(gtfs_zip: Path, radius_m: float = 380.0) -> dict:
    with zipfile.ZipFile(gtfs_zip) as zf:
        required = {"routes.txt", "trips.txt", "shapes.txt", "stops.txt"}
        missing = sorted(required.difference(zf.namelist()))
        if missing:
            raise ValueError(f"GTFS missing required files: {', '.join(missing)}")
        routes_rows = read_csv(zf, "routes.txt")
        trips_rows = read_csv(zf, "trips.txt")
        shapes_rows = read_csv(zf, "shapes.txt")
        stops_rows = read_csv(zf, "stops.txt")

    routes: dict[str, dict] = {}
    for row in routes_rows:
        try:
            route_type = int(row.get("route_type", "-1"))
        except ValueError:
            continue
        if route_type not in SURFACE_ROUTE_TYPES:
            continue
        route_id = row.get("route_id", "")
        if not route_id:
            continue
        routes[route_id] = {
            "route_id": route_id,
            "short_name": row.get("route_short_name", ""),
            "long_name": row.get("route_long_name", ""),
            "mode": SURFACE_ROUTE_TYPES[route_type],
            "color": row.get("route_color", ""),
            "text_color": row.get("route_text_color", ""),
        }

    shape_routes: dict[str, set[str]] = defaultdict(set)
    for row in trips_rows:
        route_id = row.get("route_id", "")
        shape_id = row.get("shape_id", "")
        if route_id in routes and shape_id:
            shape_routes[shape_id].add(route_id)

    raw_shapes: dict[str, list[tuple[int, list[float]]]] = defaultdict(list)
    for row in shapes_rows:
        shape_id = row.get("shape_id", "")
        if shape_id not in shape_routes:
            continue
        try:
            seq = int(row.get("shape_pt_sequence", "0"))
            lat = float(row["shape_pt_lat"])
            lon = float(row["shape_pt_lon"])
        except (KeyError, ValueError):
            continue
        raw_shapes[shape_id].append((seq, metric_point(lat, lon, *DEFAULT_ORIGIN)))

    shapes: list[dict] = []
    active_route_ids: set[str] = set()
    for shape_id, values in raw_shapes.items():
        points = [point for _, point in sorted(values)]
        if len(points) < 2:
            continue
        if min(corridor_distance((p[0], p[1]), DEFAULT_ANCHORS) for p in points) > radius_m:
            continue
        route_ids = sorted(shape_routes[shape_id])
        active_route_ids.update(route_ids)
        shapes.append({"shape_id": shape_id, "route_ids": route_ids, "points": points})

    stops: list[dict] = []
    for row in stops_rows:
        try:
            point = metric_point(float(row["stop_lat"]), float(row["stop_lon"]), *DEFAULT_ORIGIN)
        except (KeyError, ValueError):
            continue
        if corridor_distance((point[0], point[1]), DEFAULT_ANCHORS) > radius_m:
            continue
        stops.append({
            "stop_id": row.get("stop_id", ""),
            "name": row.get("stop_name", ""),
            "point": point,
        })

    filtered_routes = [routes[rid] for rid in sorted(active_route_ids)]
    return {
        "format": "grand-bruxelles-stib-gtfs-v1",
        "source": "STIB-MIVB – Open Data via Belgian Mobility Open Data Portal",
        "source_url": "https://datasets.api.production.belgianmobility.io/api/datasets-static/gtfs",
        "license": "CC-BY-4.0",
        "attribution": "Source: STIB-MIVB – Open Data – date of dataset update",
        "origin": {"lat": DEFAULT_ORIGIN[0], "lon": DEFAULT_ORIGIN[1]},
        "selection_radius_m": radius_m,
        "routes": filtered_routes,
        "shapes": shapes,
        "stops": stops,
        "stats": {
            "routes": len(filtered_routes),
            "bus_routes": sum(r["mode"] == "bus" for r in filtered_routes),
            "tram_routes": sum(r["mode"] == "tram" for r in filtered_routes),
            "shapes": len(shapes),
            "stops": len(stops),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--radius", type=float, default=380.0)
    args = parser.parse_args()
    data = convert(args.input, args.radius)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("STIB_GTFS_CONVERT_OK:", data["stats"], "->", args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
