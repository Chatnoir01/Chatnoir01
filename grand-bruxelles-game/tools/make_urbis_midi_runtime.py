#!/usr/bin/env python3
"""Build a compact runtime dataset from official UrbIS Midi GeoJSON.

Geometry stays exact in plan view. Building heights are explicitly temporary
until UrbIS Landscape/LiDAR heights are integrated; the runtime records that
provenance so visual approximations cannot be mistaken for surveyed heights.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


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


def clean_ring(ring: list[list[float]]) -> list[list[float]]:
    points = [[round(float(p[0]), 3), round(float(p[1]), 3)] for p in ring if len(p) >= 2]
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    out: list[list[float]] = []
    for point in points:
        if not out or point != out[-1]:
            out.append(point)
    return out


def centroid(ring: list[list[float]]) -> tuple[float, float]:
    if not ring:
        return 0.0, 0.0
    return (
        sum(p[0] for p in ring) / len(ring),
        sum(p[1] for p in ring) / len(ring),
    )


def in_radius(ring: list[list[float]], radius: float) -> bool:
    cx, cz = centroid(ring)
    return math.hypot(cx, cz) <= radius


def height_guess(area: float, feature_id: str) -> float:
    # Temporary massing only. The plan geometry is official; vertical geometry
    # will be replaced by UrbIS Landscape/LiDAR-derived heights.
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
    digest = hashlib.sha1(feature_id.encode("utf-8")).digest()[0]
    variation = (-1, 0, 1)[digest % 3] * 2.4
    return round(max(4.2, base + variation), 2)


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def official_level(properties: dict[str, Any]) -> float:
    """Return the official relative UrbIS level without flattening it to zero.

    Paradigm UrbIS Land Cover product specification, section 4.1.3.7:
    https://urbisdownload.datastore.brussels/UrbIS/TechSpec/LandCover_TechSpec_FR20240401.pdf
    """
    raw_level = properties.get("LVL")
    if raw_level in (None, ""):
        raise ValueError("UrbIS street surface is missing its official LVL attribute")
    level = float(raw_level)
    if not math.isfinite(level):
        raise ValueError(f"Invalid UrbIS street-surface LVL: {raw_level!r}")
    return round(level, 3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--surfaces", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--radius", type=float, default=610.0)
    parser.add_argument("--min-building-area", type=float, default=14.0)
    parser.add_argument("--min-surface-area", type=float, default=3.0)
    args = parser.parse_args()

    buildings_doc = load(args.buildings)
    surfaces_doc = load(args.surfaces)

    buildings: list[dict[str, Any]] = []
    for feature in buildings_doc.get("features", []):
        props = feature.get("properties", {}) or {}
        area = float(props.get("AREA") or 0.0)
        if area < args.min_building_area:
            continue
        for ring in outer_rings(feature.get("geometry")):
            clean = clean_ring(ring)
            if len(clean) < 3 or not in_radius(clean, args.radius):
                continue
            fid = str(props.get("INSPIRE_ID") or feature.get("id") or "")
            buildings.append({
                "id": fid,
                "area": round(area, 2),
                "footprint": clean,
                "height": height_guess(area, fid),
                "height_source": "temporary_area_heuristic",
            })

    surfaces: list[dict[str, Any]] = []
    surface_level_count = 0
    non_surface_level_count = 0
    for feature in surfaces_doc.get("features", []):
        props = feature.get("properties", {}) or {}
        area = float(props.get("AREA") or 0.0)
        if area < args.min_surface_area:
            continue
        level = official_level(props)
        for ring in outer_rings(feature.get("geometry")):
            clean = clean_ring(ring)
            if len(clean) < 3 or not in_radius(clean, args.radius):
                continue
            if math.isclose(level, 0.0, abs_tol=0.001):
                surface_level_count += 1
            else:
                non_surface_level_count += 1
            surfaces.append({
                "id": str(props.get("INSPIRE_ID") or feature.get("id") or ""),
                "type": str(props.get("TYPE") or ""),
                "level": level,
                "street_fr": str(props.get("STRNAMEFRE") or ""),
                "street_nl": str(props.get("STRNAMEDUT") or ""),
                "area": round(area, 2),
                "polygon": clean,
            })

    buildings.sort(key=lambda item: (round(math.hypot(*centroid(item["footprint"])), 3), -item["area"], item["id"]))
    surfaces.sort(key=lambda item: (round(math.hypot(*centroid(item["polygon"])), 3), item["type"], item["id"]))

    output = {
        "format": "grand-bruxelles-urbis-midi-runtime-v1",
        "source": "Paradigm UrbIS WFS / EPSG:31370",
        "coordinate_system": {
            "local_origin": "Gare du Midi Lambert72 control point",
            "axes": "x=east, z=south",
            "units": "metres",
            "world_anchor_osm": [-668.5, 627.84],
        },
        "accuracy": {
            "plan_geometry": "official_urbis",
            "street_surface_levels": "official_urbis",
            "building_heights": "temporary_area_heuristic_pending_urbis_landscape_or_lidar",
        },
        "radius_m": args.radius,
        "stats": {
            "buildings": len(buildings),
            "street_surfaces": len(surfaces),
            "street_surfaces_surface_level": surface_level_count,
            "street_surfaces_non_surface_level": non_surface_level_count,
        },
        "buildings": buildings,
        "street_surfaces": surfaces,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print("UrbIS Midi runtime:", output["stats"], "bytes:", args.output.stat().st_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
