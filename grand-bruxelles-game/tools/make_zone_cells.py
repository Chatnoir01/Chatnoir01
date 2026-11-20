#!/usr/bin/env python3
"""Generate deterministic Lambert72 work cells intersecting an official boundary.

Input must be GeoJSON already expressed in EPSG:31370. Unlike an envelope-only
grid, this tool keeps only cells that actually intersect the supplied Polygon or
MultiPolygon geometry. Cell IDs are derived from the globally aligned Lambert72
bbox, not from a municipality name, so the same 500 m square shared by two
municipalities has exactly one identity across the whole Brussels world.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable

CRS = "EPSG:31370"
DEFAULT_CELL_SIZE = 500.0
Point = tuple[float, float]
Polygon = list[list[Point]]
BBox = tuple[float, float, float, float]


def iter_geometries(payload: dict[str, Any]) -> Iterable[dict[str, Any]]:
    payload_type = payload.get("type")
    if payload_type == "FeatureCollection":
        for feature in payload.get("features", []):
            if isinstance(feature, dict):
                yield from iter_geometries(feature)
        return
    if payload_type == "Feature":
        geometry = payload.get("geometry")
        if isinstance(geometry, dict):
            yield from iter_geometries(geometry)
        return
    if payload_type == "GeometryCollection":
        for geometry in payload.get("geometries", []):
            if isinstance(geometry, dict):
                yield from iter_geometries(geometry)
        return
    if payload_type in {"Polygon", "MultiPolygon"}:
        yield payload


def _ring(raw_ring: object) -> list[Point]:
    if not isinstance(raw_ring, list):
        return []
    ring: list[Point] = []
    for raw in raw_ring:
        if not isinstance(raw, list) or len(raw) < 2:
            continue
        if not isinstance(raw[0], (int, float)) or not isinstance(raw[1], (int, float)):
            continue
        point = (float(raw[0]), float(raw[1]))
        if not ring or point != ring[-1]:
            ring.append(point)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring.pop()
    return ring


def geometry_polygons(geometry: dict[str, Any]) -> list[Polygon]:
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    polygons: list[Polygon] = []
    if kind == "Polygon" and isinstance(coords, list):
        polygon = [_ring(raw_ring) for raw_ring in coords]
        polygon = [ring for ring in polygon if len(ring) >= 3]
        if polygon:
            polygons.append(polygon)
    elif kind == "MultiPolygon" and isinstance(coords, list):
        for raw_polygon in coords:
            if not isinstance(raw_polygon, list):
                continue
            polygon = [_ring(raw_ring) for raw_ring in raw_polygon]
            polygon = [ring for ring in polygon if len(ring) >= 3]
            if polygon:
                polygons.append(polygon)
    return polygons


def collect_polygons(payload: dict[str, Any]) -> list[Polygon]:
    polygons: list[Polygon] = []
    for geometry in iter_geometries(payload):
        polygons.extend(geometry_polygons(geometry))
    if not polygons:
        raise ValueError("input contains no Polygon or MultiPolygon geometry")
    return polygons


def collect_positions(payload: dict[str, Any]) -> list[Point]:
    return [point for polygon in collect_polygons(payload) for ring in polygon for point in ring]


def aligned_floor(value: float, step: float) -> float:
    return math.floor(value / step) * step


def aligned_ceil(value: float, step: float) -> float:
    return math.ceil(value / step) * step


def _point_on_segment(point: Point, a: Point, b: Point, epsilon: float = 1e-9) -> bool:
    px, py = point
    ax, ay = a
    bx, by = b
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if abs(cross) > epsilon:
        return False
    return (
        min(ax, bx) - epsilon <= px <= max(ax, bx) + epsilon
        and min(ay, by) - epsilon <= py <= max(ay, by) + epsilon
    )


def point_in_ring(point: Point, ring: list[Point]) -> bool:
    if len(ring) < 3:
        return False
    inside = False
    px, py = point
    for index, a in enumerate(ring):
        b = ring[(index + 1) % len(ring)]
        if _point_on_segment(point, a, b):
            return True
        ax, ay = a
        bx, by = b
        if (ay > py) == (by > py):
            continue
        crossing_x = (bx - ax) * (py - ay) / (by - ay) + ax
        if px < crossing_x:
            inside = not inside
    return inside


def point_in_polygon(point: Point, polygon: Polygon) -> bool:
    if not polygon or not point_in_ring(point, polygon[0]):
        return False
    for hole in polygon[1:]:
        if point_in_ring(point, hole):
            return False
    return True


def _orientation(a: Point, b: Point, c: Point, epsilon: float = 1e-9) -> int:
    value = (b[1] - a[1]) * (c[0] - b[0]) - (b[0] - a[0]) * (c[1] - b[1])
    if abs(value) <= epsilon:
        return 0
    return 1 if value > 0 else 2


def segments_intersect(a: Point, b: Point, c: Point, d: Point) -> bool:
    o1 = _orientation(a, b, c)
    o2 = _orientation(a, b, d)
    o3 = _orientation(c, d, a)
    o4 = _orientation(c, d, b)
    if o1 != o2 and o3 != o4:
        return True
    if o1 == 0 and _point_on_segment(c, a, b):
        return True
    if o2 == 0 and _point_on_segment(d, a, b):
        return True
    if o3 == 0 and _point_on_segment(a, c, d):
        return True
    if o4 == 0 and _point_on_segment(b, c, d):
        return True
    return False


def _point_in_bbox(point: Point, bbox: BBox) -> bool:
    min_e, min_n, max_e, max_n = bbox
    return min_e <= point[0] <= max_e and min_n <= point[1] <= max_n


def _bbox_edges(bbox: BBox) -> list[tuple[Point, Point]]:
    min_e, min_n, max_e, max_n = bbox
    sw = (min_e, min_n)
    se = (max_e, min_n)
    ne = (max_e, max_n)
    nw = (min_e, max_n)
    return [(sw, se), (se, ne), (ne, nw), (nw, sw)]


def cell_intersects_polygon(bbox: BBox, polygon: Polygon) -> bool:
    if not polygon:
        return False
    all_points = [point for ring in polygon for point in ring]
    poly_min_e = min(point[0] for point in all_points)
    poly_min_n = min(point[1] for point in all_points)
    poly_max_e = max(point[0] for point in all_points)
    poly_max_n = max(point[1] for point in all_points)
    min_e, min_n, max_e, max_n = bbox
    if poly_max_e < min_e or poly_min_e > max_e or poly_max_n < min_n or poly_min_n > max_n:
        return False

    for point in all_points:
        if _point_in_bbox(point, bbox):
            return True

    corners: list[Point] = [
        (min_e, min_n),
        (max_e, min_n),
        (max_e, max_n),
        (min_e, max_n),
        ((min_e + max_e) * 0.5, (min_n + max_n) * 0.5),
    ]
    if any(point_in_polygon(corner, polygon) for corner in corners):
        return True

    cell_edges = _bbox_edges(bbox)
    for ring in polygon:
        for index, a in enumerate(ring):
            b = ring[(index + 1) % len(ring)]
            if any(segments_intersect(a, b, c, d) for c, d in cell_edges):
                return True
    return False


def cell_intersects_any(bbox: BBox, polygons: list[Polygon]) -> bool:
    return any(cell_intersects_polygon(bbox, polygon) for polygon in polygons)


def _coord_token(value: float) -> str:
    rounded = round(value)
    if math.isclose(value, rounded, abs_tol=1e-9):
        return str(int(rounded)).replace("-", "m")
    return f"{value:.3f}".rstrip("0").rstrip(".").replace("-", "m").replace(".", "p")


def canonical_cell_id(min_e: float, min_n: float, cell_size: float) -> str:
    return f"bxl-e{_coord_token(min_e)}-n{_coord_token(min_n)}-s{_coord_token(cell_size)}"


def build_cells(
    min_e: float,
    min_n: float,
    max_e: float,
    max_n: float,
    cell_size: float,
    zone_id: str,
    polygons: list[Polygon] | None = None,
) -> list[dict[str, Any]]:
    start_e = aligned_floor(min_e, cell_size)
    start_n = aligned_floor(min_n, cell_size)
    end_e = aligned_ceil(max_e, cell_size)
    end_n = aligned_ceil(max_n, cell_size)
    cols = int(round((end_e - start_e) / cell_size))
    rows = int(round((end_n - start_n) / cell_size))
    cells: list[dict[str, Any]] = []

    for row in range(rows):
        for col in range(cols):
            cell_min_e = start_e + col * cell_size
            cell_min_n = start_n + row * cell_size
            cell_max_e = cell_min_e + cell_size
            cell_max_n = cell_min_n + cell_size
            bbox: BBox = (cell_min_e, cell_min_n, cell_max_e, cell_max_n)
            if polygons is not None and not cell_intersects_any(bbox, polygons):
                continue
            cell_id = canonical_cell_id(cell_min_e, cell_min_n, cell_size)
            cells.append(
                {
                    "id": cell_id,
                    "zone_id": zone_id,
                    "row": row,
                    "col": col,
                    "bbox": list(bbox),
                    "fetch_command": (
                        "python tools/build_urbis_cell.py "
                        f"--cell-id {cell_id} "
                        f"--output-dir data/urbis/remaining_brussels/cells/{cell_id} "
                        f"--bbox {cell_min_e},{cell_min_n},{cell_max_e},{cell_max_n}"
                    ),
                }
            )
    return cells


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create globally aligned 500 m Lambert72 cells intersecting a Brussels zone"
    )
    parser.add_argument("--boundary", type=Path, required=True, help="official GeoJSON in EPSG:31370")
    parser.add_argument("--zone-id", required=True, help="stable lowercase zone identifier")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cell-size", type=float, default=DEFAULT_CELL_SIZE)
    args = parser.parse_args()

    if args.cell_size <= 0:
        parser.error("--cell-size must be greater than zero")
    if not args.zone_id or any(char.isspace() for char in args.zone_id):
        parser.error("--zone-id must be a non-empty identifier without spaces")

    payload = json.loads(args.boundary.read_text(encoding="utf-8"))
    polygons = collect_polygons(payload)
    positions = [point for polygon in polygons for ring in polygon for point in ring]
    eastings = [position[0] for position in positions]
    northings = [position[1] for position in positions]
    source_bbox = [min(eastings), min(northings), max(eastings), max(northings)]
    if source_bbox[0] < 10_000 or source_bbox[1] < 10_000:
        raise ValueError("boundary does not look like EPSG:31370 Lambert72 metres")

    envelope_cols = int((aligned_ceil(source_bbox[2], args.cell_size) - aligned_floor(source_bbox[0], args.cell_size)) / args.cell_size)
    envelope_rows = int((aligned_ceil(source_bbox[3], args.cell_size) - aligned_floor(source_bbox[1], args.cell_size)) / args.cell_size)
    envelope_cell_count = envelope_cols * envelope_rows
    cells = build_cells(*source_bbox, args.cell_size, args.zone_id, polygons)
    manifest = {
        "format": "grand-bruxelles-zone-cells-v2",
        "zone_id": args.zone_id,
        "crs": CRS,
        "boundary_source": str(args.boundary),
        "source_bbox": source_bbox,
        "cell_size_m": args.cell_size,
        "cell_id_scheme": "global Lambert72 minE/minN + cell size",
        "envelope_cell_count": envelope_cell_count,
        "cell_count": len(cells),
        "cells": cells,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"{args.zone_id}: {len(cells)}/{envelope_cell_count} intersecting cells -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
