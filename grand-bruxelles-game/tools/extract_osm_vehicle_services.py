#!/usr/bin/env python3
"""Extract vehicle repair services from a raw Brussels Overpass payload.

This intentionally keeps garages separate from city geometry. Only explicit
OSM repair-service tags are accepted; no repair location is invented.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_378_137.0
DEFAULT_ORIGIN = (50.8419, 4.3480)
REPAIR_SHOPS = {"car_repair": "garage", "tyres": "tyres"}


def metric_point(lat: float, lon: float, origin_lat: float, origin_lon: float) -> list[float]:
    lat0 = math.radians(origin_lat)
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(lat0)
    north = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    return [round(x, 3), round(-north, 3)]


def service_kind(tags: dict[str, Any]) -> str | None:
    shop = str(tags.get("shop", "")).strip().lower()
    if shop in REPAIR_SHOPS:
        return REPAIR_SHOPS[shop]
    if str(tags.get("amenity", "")).strip().lower() == "car_repair":
        return "garage"
    return None


def element_center(element: dict[str, Any]) -> tuple[float, float] | None:
    if element.get("type") == "node" and "lat" in element and "lon" in element:
        return float(element["lat"]), float(element["lon"])
    geometry = element.get("geometry", []) or []
    coords = [
        (float(point["lat"]), float(point["lon"]))
        for point in geometry
        if "lat" in point and "lon" in point
    ]
    if not coords:
        return None
    return (
        sum(lat for lat, _ in coords) / len(coords),
        sum(lon for _, lon in coords) / len(coords),
    )


def service_record(element: dict[str, Any], origin: tuple[float, float]) -> dict[str, Any] | None:
    tags = element.get("tags", {}) or {}
    kind = service_kind(tags)
    center = element_center(element)
    if kind is None or center is None:
        return None
    lat, lon = center
    return {
        "osm_type": element.get("type", ""),
        "osm_id": element.get("id"),
        "kind": kind,
        "name": tags.get("name", ""),
        "operator": tags.get("operator", ""),
        "brand": tags.get("brand", ""),
        "opening_hours": tags.get("opening_hours", ""),
        "street": tags.get("addr:street", ""),
        "housenumber": tags.get("addr:housenumber", ""),
        "point": metric_point(lat, lon, *origin),
    }


def convert(data: dict[str, Any], origin: tuple[float, float] = DEFAULT_ORIGIN) -> dict[str, Any]:
    services: list[dict[str, Any]] = []
    seen: set[tuple[str, int]] = set()
    for element in data.get("elements", []):
        record = service_record(element, origin)
        if record is None:
            continue
        key = (str(record["osm_type"]), int(record["osm_id"] or 0))
        if key in seen:
            continue
        seen.add(key)
        services.append(record)

    services.sort(key=lambda item: (str(item["kind"]), str(item["name"]), int(item["osm_id"] or 0)))
    return {
        "format": "grand-bruxelles-vehicle-services-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "origin": {"lat": origin[0], "lon": origin[1]},
        "selection_policy": "explicit shop=car_repair/shop=tyres/amenity=car_repair only",
        "stats": {
            "services": len(services),
            "garages": sum(item["kind"] == "garage" for item in services),
            "tyre_services": sum(item["kind"] == "tyres" for item in services),
            "named": sum(bool(item["name"]) for item in services),
        },
        "services": services,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw = json.loads(args.input.read_text(encoding="utf-8"))
    data = convert(raw)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("OSM_VEHICLE_SERVICES_OK:", data["stats"], "->", args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
