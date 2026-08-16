#!/usr/bin/env python3
"""Cross-check the OSM King Baudouin Stadium envelope against UrbIS buildings.

OSM is used only as a complementary semantic envelope (way 253875451). The
candidate construction geometry and identifiers remain UrbIS. The report is
strictly evidence: it does not auto-promote a final photo-match target.
"""

from __future__ import annotations

import argparse
import json
import math
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from pyproj import Transformer
from shapely.geometry import Polygon, shape
from shapely.ops import unary_union

OSM_WAY_ID = 253875451
OSM_API_URL = f"https://api.openstreetmap.org/api/0.6/way/{OSM_WAY_ID}/full"
OSM_LICENSE = "ODbL 1.0"
CRS = "EPSG:31370"


def load_osm_way_xml(path: str = "") -> bytes:
    if path:
        return Path(path).read_bytes()
    request = urllib.request.Request(OSM_API_URL, headers={"User-Agent": "GrandBruxellesGame/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def parse_osm_stadium(xml_bytes: bytes) -> tuple[Polygon, dict[str, Any]]:
    root = ET.fromstring(xml_bytes)
    nodes: dict[int, tuple[float, float]] = {}
    for node in root.findall("node"):
        nodes[int(node.attrib["id"])] = (float(node.attrib["lon"]), float(node.attrib["lat"]))

    target = None
    for way in root.findall("way"):
        if int(way.attrib.get("id", -1)) == OSM_WAY_ID:
            target = way
            break
    if target is None:
        raise ValueError(f"OSM way {OSM_WAY_ID} missing from response")

    tags = {tag.attrib["k"]: tag.attrib["v"] for tag in target.findall("tag")}
    if tags.get("leisure") != "stadium":
        raise ValueError("OSM semantic envelope is no longer tagged leisure=stadium")

    lon_lat = [nodes[int(nd.attrib["ref"])] for nd in target.findall("nd")]
    if len(lon_lat) < 4:
        raise ValueError("OSM stadium envelope has too few nodes")
    transformer = Transformer.from_crs("EPSG:4326", CRS, always_xy=True)
    lambert = [transformer.transform(lon, lat) for lon, lat in lon_lat]
    polygon = Polygon(lambert)
    if not polygon.is_valid:
        polygon = polygon.buffer(0)
    if polygon.is_empty or polygon.area <= 0.0:
        raise ValueError("OSM stadium envelope is empty after projection")

    metadata = {
        "way_id": OSM_WAY_ID,
        "version": int(target.attrib.get("version", 0)),
        "timestamp": target.attrib.get("timestamp", ""),
        "changeset": int(target.attrib.get("changeset", 0)),
        "tags": tags,
        "source_url": f"https://www.openstreetmap.org/way/{OSM_WAY_ID}",
        "api_url": OSM_API_URL,
        "license": OSM_LICENSE,
    }
    return polygon, metadata


def oriented_rectangle_metrics(geometry: Any) -> dict[str, float] | None:
    if geometry is None or geometry.is_empty:
        return None
    rectangle = geometry.minimum_rotated_rectangle
    if rectangle.is_empty or not hasattr(rectangle, "exterior"):
        return None
    coordinates = list(rectangle.exterior.coords)
    if len(coordinates) < 5:
        return None
    edges: list[tuple[float, float, float]] = []
    for index in range(4):
        x0, y0 = coordinates[index]
        x1, y1 = coordinates[index + 1]
        dx = float(x1 - x0)
        dy = float(y1 - y0)
        edges.append((math.hypot(dx, dy), dx, dy))
    longest = max(edges, key=lambda edge: edge[0])
    shortest = min(edges, key=lambda edge: edge[0])
    return {
        "length_m": longest[0],
        "width_m": shortest[0],
        "long_axis_angle_deg_lambert": math.degrees(math.atan2(longest[2], longest[1])) % 180.0,
        "rectangle_area_m2": float(rectangle.area),
    }


def build_overlap_audit(
    feature_collection: dict[str, Any], stadium_polygon: Polygon, osm_metadata: dict[str, Any]
) -> dict[str, Any]:
    hits: list[dict[str, Any]] = []
    hit_geometries = []
    clipped_geometries = []
    for index, feature in enumerate(feature_collection.get("features", [])):
        geometry = shape(feature.get("geometry"))
        if geometry.is_empty or not geometry.intersects(stadium_polygon):
            continue
        intersection = geometry.intersection(stadium_polygon)
        intersection_area = float(intersection.area)
        if intersection_area < 1.0:
            continue
        properties = feature.get("properties", {})
        feature_area = float(geometry.area)
        hits.append(
            {
                "feature_index": index,
                "feature_id": feature.get("id"),
                "inspire_id": properties.get("INSPIRE_ID"),
                "block_id": properties.get("BLOCK_ID"),
                "urbis_area_m2": round(feature_area, 3),
                "intersection_area_m2": round(intersection_area, 3),
                "feature_inside_osm_ratio": round(intersection_area / max(feature_area, 1e-9), 6),
                "osm_envelope_coverage_ratio": round(intersection_area / stadium_polygon.area, 6),
                "centroid_lambert72": [round(float(geometry.centroid.x), 3), round(float(geometry.centroid.y), 3)],
                "bounds_lambert72": [round(float(v), 3) for v in geometry.bounds],
            }
        )
        hit_geometries.append(geometry)
        clipped_geometries.append(intersection)

    hits.sort(key=lambda item: (-item["intersection_area_m2"], item["feature_index"]))
    clipped_union = unary_union(clipped_geometries) if clipped_geometries else None
    full_union = unary_union(hit_geometries) if hit_geometries else None
    full_union_oriented = oriented_rectangle_metrics(full_union)
    return {
        "status": "osm_semantic_envelope_vs_urbis_geometry_evidence_only",
        "crs": CRS,
        "osm": osm_metadata,
        "osm_envelope_area_m2": round(float(stadium_polygon.area), 3),
        "osm_envelope_centroid_lambert72": [
            round(float(stadium_polygon.centroid.x), 3),
            round(float(stadium_polygon.centroid.y), 3),
        ],
        "intersecting_urbis_feature_count": len(hits),
        "intersecting_urbis_features": hits,
        "clipped_urbis_union_coverage_ratio": (
            round(float(clipped_union.area / stadium_polygon.area), 6) if clipped_union is not None else 0.0
        ),
        "clipped_urbis_union_centroid_lambert72": (
            [round(float(clipped_union.centroid.x), 3), round(float(clipped_union.centroid.y), 3)]
            if clipped_union is not None and not clipped_union.is_empty
            else None
        ),
        "full_intersecting_urbis_union_centroid_lambert72": (
            [round(float(full_union.centroid.x), 3), round(float(full_union.centroid.y), 3)]
            if full_union is not None and not full_union.is_empty
            else None
        ),
        "full_intersecting_urbis_union_oriented_rectangle": (
            {key: round(float(value), 3) for key, value in full_union_oriented.items()}
            if full_union_oriented is not None
            else None
        ),
        "decision_rule": (
            "OSM supplies only the semantic stadium envelope. A final target may use only an explicitly "
            "validated set of UrbIS constructions; do not use the OSM polygon itself as final game geometry."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--buildings",
        default="grand-bruxelles-game/data/urbis/laeken_jette/buildings.geojson",
    )
    parser.add_argument("--osm-xml", default="")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    stadium_polygon, metadata = parse_osm_stadium(load_osm_way_xml(args.osm_xml))
    buildings = json.loads(Path(args.buildings).read_text(encoding="utf-8"))
    audit = build_overlap_audit(buildings, stadium_polygon, metadata)
    encoded = json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        Path(args.output).write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    if audit["intersecting_urbis_feature_count"] == 0:
        raise SystemExit("HEYSEL_OSM_URBIS_OVERLAP_FAIL: no intersecting UrbIS construction")
    print(
        "HEYSEL_OSM_URBIS_OVERLAP_OK: %d UrbIS features, coverage %.3f"
        % (audit["intersecting_urbis_feature_count"], audit["clipped_urbis_union_coverage_ratio"])
    )


if __name__ == "__main__":
    main()
