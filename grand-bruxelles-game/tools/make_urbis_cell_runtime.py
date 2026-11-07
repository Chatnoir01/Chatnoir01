#!/usr/bin/env python3
"""Build one compact game runtime cell from raw EPSG:31370 UrbIS layers.

Features returned by bbox WFS queries can cross cell boundaries and therefore be
returned in adjacent cells. Ownership is deterministic: a polygon belongs to the
half-open cell containing its plan centroid. This prevents duplicate buildings
and street surfaces at streaming seams.

The current prototype OSM world uses lat/lon origin (50.8419, 4.3480), where
Bruxelles-Midi is already located at (-668.5, 627.84). UrbIS uses the project's
Lambert72 Midi control point as its metric origin, so every UrbIS coordinate is
translated by this single global world anchor. The translation is baked here,
not independently in each zone, keeping all cells and the existing prototype in
one world coordinate system.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
WORLD_ANCHOR_X = -668.5
WORLD_ANCHOR_Z = 627.84


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    values = tuple(float(part.strip()) for part in raw.split(","))
    if len(values) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    min_e, min_n, max_e, max_n = values
    if min_e >= max_e or min_n >= max_n:
        raise argparse.ArgumentTypeError("invalid bbox")
    return min_e, min_n, max_e, max_n


def outer_rings(geometry: dict[str, Any] | None) -> list[list[list[float]]]:
    if not geometry:
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [polygon[0] for polygon in coords if polygon]
    return []


def clean_lambert_ring(ring: list[list[float]]) -> list[list[float]]:
    points = [[float(point[0]), float(point[1])] for point in ring if len(point) >= 2]
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    cleaned: list[list[float]] = []
    for point in points:
        if not cleaned or point != cleaned[-1]:
            cleaned.append(point)
    return cleaned


def polygon_area(ring: list[list[float]]) -> float:
    if len(ring) < 3:
        return 0.0
    twice = 0.0
    for index, point in enumerate(ring):
        nxt = ring[(index + 1) % len(ring)]
        twice += point[0] * nxt[1] - nxt[0] * point[1]
    return abs(twice) * 0.5


def polygon_centroid(ring: list[list[float]]) -> tuple[float, float]:
    if len(ring) < 3:
        if not ring:
            return 0.0, 0.0
        return (
            sum(point[0] for point in ring) / len(ring),
            sum(point[1] for point in ring) / len(ring),
        )

    cross_sum = 0.0
    cx_sum = 0.0
    cy_sum = 0.0
    for index, point in enumerate(ring):
        nxt = ring[(index + 1) % len(ring)]
        cross = point[0] * nxt[1] - nxt[0] * point[1]
        cross_sum += cross
        cx_sum += (point[0] + nxt[0]) * cross
        cy_sum += (point[1] + nxt[1]) * cross
    if abs(cross_sum) < 1e-9:
        return (
            sum(point[0] for point in ring) / len(ring),
            sum(point[1] for point in ring) / len(ring),
        )
    return cx_sum / (3.0 * cross_sum), cy_sum / (3.0 * cross_sum)


def owns_centroid(centroid: tuple[float, float], bbox: tuple[float, float, float, float]) -> bool:
    easting, northing = centroid
    min_e, min_n, max_e, max_n = bbox
    return min_e <= easting < max_e and min_n <= northing < max_n


def game_point(point: list[float]) -> list[float]:
    """Convert Lambert72 plan coordinates directly into current game-world X/Z."""
    return [
        round(point[0] - ORIGIN_E + WORLD_ANCHOR_X, 3),
        round(-(point[1] - ORIGIN_N) + WORLD_ANCHOR_Z, 3),
    ]


def game_ring(ring: list[list[float]]) -> list[list[float]]:
    return [game_point(point) for point in ring]


def feature_id(feature: dict[str, Any], props: dict[str, Any]) -> str:
    return str(props.get("INSPIRE_ID") or feature.get("id") or "")


def height_guess(area: float, identifier: str) -> float:
    if area < 35:
        base = 6.8
    elif area < 90:
        base = 9.8
    elif area < 200:
        base = 12.8
    elif area < 450:
        base = 15.8
    else:
        base = 19.5
    digest = hashlib.sha1(identifier.encode("utf-8")).digest()[0]
    variation = (-1, 0, 1)[digest % 3] * 2.4
    return round(max(4.2, base + variation), 2)


def build_runtime(
    buildings_doc: dict[str, Any],
    surfaces_doc: dict[str, Any],
    bbox: tuple[float, float, float, float],
    cell_id: str,
    min_building_area: float = 14.0,
    min_surface_area: float = 3.0,
) -> dict[str, Any]:
    buildings: list[dict[str, Any]] = []
    surfaces: list[dict[str, Any]] = []

    for feature in buildings_doc.get("features", []):
        props = feature.get("properties", {}) or {}
        for raw_ring in outer_rings(feature.get("geometry")):
            ring = clean_lambert_ring(raw_ring)
            area = polygon_area(ring)
            if len(ring) < 3 or area < min_building_area:
                continue
            center = polygon_centroid(ring)
            if not owns_centroid(center, bbox):
                continue
            identifier = feature_id(feature, props)
            buildings.append(
                {
                    "id": identifier,
                    "area": round(area, 2),
                    "footprint": game_ring(ring),
                    "height": height_guess(area, identifier),
                    "height_source": "temporary_area_heuristic",
                }
            )

    for feature in surfaces_doc.get("features", []):
        props = feature.get("properties", {}) or {}
        for raw_ring in outer_rings(feature.get("geometry")):
            ring = clean_lambert_ring(raw_ring)
            area = polygon_area(ring)
            if len(ring) < 3 or area < min_surface_area:
                continue
            if not owns_centroid(polygon_centroid(ring), bbox):
                continue
            surfaces.append(
                {
                    "id": feature_id(feature, props),
                    "type": str(props.get("TYPE") or ""),
                    "street_fr": str(props.get("STRNAMEFRE") or ""),
                    "street_nl": str(props.get("STRNAMEDUT") or ""),
                    "area": round(area, 2),
                    "polygon": game_ring(ring),
                }
            )

    buildings.sort(key=lambda item: item["id"])
    surfaces.sort(key=lambda item: (item["type"], item["id"]))
    return {
        "format": "grand-bruxelles-urbis-cell-runtime-v1",
        "cell_id": cell_id,
        "source": "Paradigm UrbIS WFS / EPSG:31370",
        "source_bbox": list(bbox),
        "coordinate_system": {
            "lambert_origin_e": ORIGIN_E,
            "lambert_origin_n": ORIGIN_N,
            "world_anchor_x": WORLD_ANCHOR_X,
            "world_anchor_z": WORLD_ANCHOR_Z,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
            "coordinates_are_current_game_world": True,
        },
        "ownership": "polygon centroid inside half-open source_bbox",
        "accuracy": {
            "plan_geometry": "official_urbis",
            "building_heights": "temporary_area_heuristic_pending_urbis_landscape_or_lidar",
        },
        "stats": {
            "buildings": len(buildings),
            "street_surfaces": len(surfaces),
        },
        "buildings": buildings,
        "street_surfaces": surfaces,
    }


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build one deduplicated UrbIS runtime cell")
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--surfaces", type=Path, required=True)
    parser.add_argument("--bbox", type=parse_bbox, required=True)
    parser.add_argument("--cell-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-building-area", type=float, default=14.0)
    parser.add_argument("--min-surface-area", type=float, default=3.0)
    args = parser.parse_args()

    runtime = build_runtime(
        load(args.buildings),
        load(args.surfaces),
        args.bbox,
        args.cell_id,
        args.min_building_area,
        args.min_surface_area,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(runtime, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{args.cell_id}: {runtime['stats']} -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
