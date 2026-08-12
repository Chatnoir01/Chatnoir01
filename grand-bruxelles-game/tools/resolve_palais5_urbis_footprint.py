#!/usr/bin/env python3
"""Resolve named Brussels Expo Palais 5 from OSM to the official UrbIS building footprint.

OSM is used only as a semantic/name locator. The selected geometry remains the
committed Paradigm UrbIS Buildings footprint in project coordinates.
"""

from __future__ import annotations

import json
import math
import urllib.parse
import urllib.request
from pathlib import Path

from pyproj import Transformer

OVERPASS = "https://overpass-api.de/api/interpreter"
BUILDINGS = Path("data/urbis/laeken_jette/buildings.game.json")
OUTPUT = Path("data/sources/laeken_jette/palais5_urbis_match.json")
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
ATOMIUM_LOCAL = (224.92615906274295, -6553.143077999353)


def fetch_osm() -> dict:
    # Broad enough to survive naming/language differences but constrained to the
    # Heysel plateau. Relation/way candidates are returned with full geometry.
    query = r'''[out:json][timeout:40];
(
  way["name"~"Palais 5|Paleis 5|Palace 5",i](50.89,4.32,50.91,4.35);
  relation["name"~"Palais 5|Paleis 5|Palace 5",i](50.89,4.32,50.91,4.35);
  way["ref"="5"]["building"](50.89,4.32,50.91,4.35);
);
out tags center geom;'''
    body = urllib.parse.urlencode({"data": query}).encode()
    request = urllib.request.Request(
        OVERPASS,
        data=body,
        headers={"User-Agent": "Grand-Bruxelles-Game/1.0 Palais5 semantic locator"},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))


def osm_candidate_point(element: dict, transformer: Transformer) -> tuple[float, float] | None:
    center = element.get("center")
    if isinstance(center, dict) and "lon" in center and "lat" in center:
        e, n = transformer.transform(float(center["lon"]), float(center["lat"]))
        return e - ORIGIN_E, -(n - ORIGIN_N)
    geom = element.get("geometry")
    if isinstance(geom, list) and geom:
        pts = []
        for p in geom:
            if isinstance(p, dict) and "lon" in p and "lat" in p:
                e, n = transformer.transform(float(p["lon"]), float(p["lat"]))
                pts.append((e - ORIGIN_E, -(n - ORIGIN_N)))
        if pts:
            return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    return None


def iter_positions(value):
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            yield float(value[0]), float(value[1])
        else:
            for child in value:
                yield from iter_positions(child)


def footprint_stats(feature: dict) -> dict | None:
    geometry = feature.get("geometry") or {}
    pts = list(iter_positions(geometry.get("coordinates", [])))
    if not pts:
        return None
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    cx = sum(xs) / len(xs)
    cz = sum(zs) / len(zs)
    # PCA major axis in X/Z for deterministic facade alignment.
    centered = [(x - cx, z - cz) for x, z in pts]
    xx = sum(x*x for x, _ in centered) / len(centered)
    zz = sum(z*z for _, z in centered) / len(centered)
    xz = sum(x*z for x, z in centered) / len(centered)
    angle = 0.5 * math.atan2(2.0*xz, xx-zz)
    axis = (math.cos(angle), math.sin(angle))
    side = (-axis[1], axis[0])
    major = [x*axis[0]+z*axis[1] for x,z in centered]
    minor = [x*side[0]+z*side[1] for x,z in centered]
    return {
        "centroid_x": cx,
        "centroid_z": cz,
        "min_x": min(xs), "max_x": max(xs), "min_z": min(zs), "max_z": max(zs),
        "pca_angle_rad": angle,
        "pca_angle_deg": math.degrees(angle),
        "major_span_m": max(major)-min(major),
        "minor_span_m": max(minor)-min(minor),
        "distance_to_atomium_m": math.hypot(cx-ATOMIUM_LOCAL[0], cz-ATOMIUM_LOCAL[1]),
    }


def main() -> int:
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    osm = fetch_osm()
    candidates = []
    for element in osm.get("elements", []):
        point = osm_candidate_point(element, transformer)
        if point is None:
            continue
        candidates.append({
            "osm_type": element.get("type"),
            "osm_id": element.get("id"),
            "tags": element.get("tags", {}),
            "local_x": point[0],
            "local_z": point[1],
        })
    if not candidates:
        raise SystemExit("No OSM Palais 5 candidate found")

    # Prefer explicit name match; use the candidate nearest the Atomium only as a
    # deterministic tie breaker if duplicate name objects exist.
    def candidate_rank(item):
        name = str(item["tags"].get("name", "")).lower()
        explicit = 0 if any(token in name for token in ("palais 5", "paleis 5", "palace 5")) else 1
        return explicit, math.hypot(item["local_x"]-ATOMIUM_LOCAL[0], item["local_z"]-ATOMIUM_LOCAL[1])
    candidates.sort(key=candidate_rank)
    locator = candidates[0]

    buildings = json.loads(BUILDINGS.read_text(encoding="utf-8"))
    matches = []
    for index, feature in enumerate(buildings.get("features", [])):
        if not isinstance(feature, dict):
            continue
        stats = footprint_stats(feature)
        if stats is None:
            continue
        distance = math.hypot(stats["centroid_x"]-locator["local_x"], stats["centroid_z"]-locator["local_z"])
        # Hall 5 is huge. Restrict to substantial footprints so nearby kiosks or
        # service buildings cannot win merely because their centroid is closer.
        area = float((feature.get("properties") or {}).get("AREA") or 0.0)
        if distance <= 160.0 and area >= 1000.0:
            matches.append({
                "feature_index": index,
                "centroid_distance_to_osm_m": distance,
                "area_m2": area,
                "properties": feature.get("properties") or {},
                **stats,
            })
    if not matches:
        raise SystemExit("No substantial UrbIS building found near OSM Palais 5 locator")
    matches.sort(key=lambda item: (item["centroid_distance_to_osm_m"], -item["area_m2"]))
    selected = matches[0]

    output = {
        "schema": 1,
        "semantic_locator_source": "OpenStreetMap Overpass",
        "semantic_locator_role": "name/identity only",
        "geometry_source": "Paradigm UrbIS Buildings WFS",
        "osm_candidates": candidates,
        "selected_osm_locator": locator,
        "urbis_candidates": matches[:12],
        "selected_urbis_feature": selected,
        "visual_policy": "Hero architecture must keep the selected UrbIS footprint/location and the DSM-derived effective height. Facade subdivision/statues are photo-guided approximations until architectural source drawings are integrated.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("PALAIS5_URBIS_MATCH_OK", json.dumps(selected, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
