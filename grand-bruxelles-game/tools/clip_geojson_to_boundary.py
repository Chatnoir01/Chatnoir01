#!/usr/bin/env python3
"""Clip Polygon/MultiPolygon GeoJSON features to an official ownership boundary.

Both inputs must already use EPSG:31370. Shapely is imported lazily so the wider
project test suite does not require it; workflows performing clipping install
Shapely explicitly. GeometryCollections are reduced to polygonal parts only.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ALLOWED = {"Polygon", "MultiPolygon"}
FORMAT = "grand-bruxelles-clipped-feature-collection-v1"


def load_collection(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("type") != "FeatureCollection":
        raise ValueError(f"expected FeatureCollection: {path}")
    crs_name = str(((payload.get("crs") or {}).get("properties") or {}).get("name") or "")
    source_crs = str(((payload.get("grand_bruxelles_source") or {}).get("crs") or ""))
    if "31370" not in crs_name and "31370" not in source_crs:
        raise ValueError(f"input does not explicitly declare EPSG:31370: {path}")
    return payload


def polygon_features(payload: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry") or {}
        if str(geometry.get("type") or "") in ALLOWED:
            result.append(feature)
    if not result:
        raise ValueError("FeatureCollection has no Polygon/MultiPolygon features")
    return result


def require_shapely():
    try:
        from shapely.geometry import GeometryCollection, MultiPolygon, Polygon, mapping, shape
        from shapely.ops import unary_union
    except ImportError as exc:
        raise RuntimeError("Shapely is required for polygon ownership clipping") from exc
    return GeometryCollection, MultiPolygon, Polygon, mapping, shape, unary_union


def polygonal_only(geometry: Any) -> Any:
    GeometryCollection, MultiPolygon, Polygon, _, _, unary_union = require_shapely()
    if geometry.is_empty:
        return geometry
    if isinstance(geometry, (Polygon, MultiPolygon)):
        return geometry
    if isinstance(geometry, GeometryCollection):
        parts = [part for part in geometry.geoms if isinstance(part, (Polygon, MultiPolygon)) and not part.is_empty]
        return unary_union(parts) if parts else geometry.__class__()
    return GeometryCollection()


def clip_collections(source: dict[str, Any], boundary: dict[str, Any], source_name: str, boundary_name: str) -> dict[str, Any]:
    _, _, _, mapping, shape, unary_union = require_shapely()
    source_features = polygon_features(source)
    boundary_features = polygon_features(boundary)
    boundary_union = unary_union([shape(feature["geometry"]) for feature in boundary_features])
    if boundary_union.is_empty or boundary_union.area <= 0:
        raise ValueError("ownership boundary union is empty")

    output_features: list[dict[str, Any]] = []
    source_area = 0.0
    clipped_area = 0.0
    for index, feature in enumerate(source_features):
        source_geometry = shape(feature["geometry"])
        if source_geometry.is_empty:
            continue
        source_area += float(source_geometry.area)
        clipped = polygonal_only(source_geometry.intersection(boundary_union))
        if clipped.is_empty or clipped.area <= 0:
            continue
        clipped_area += float(clipped.area)
        properties = dict(feature.get("properties") or {})
        properties["grand_bruxelles_clipped_to"] = boundary_name
        output_features.append(
            {
                "type": "Feature",
                "id": str(feature.get("id") or f"clipped-{index}"),
                "properties": properties,
                "geometry": mapping(clipped),
            }
        )

    if not output_features:
        raise ValueError(f"source {source_name} has no polygon area inside ownership boundary {boundary_name}")
    return {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
        "features": output_features,
        "grand_bruxelles_clip": {
            "format": FORMAT,
            "source_name": source_name,
            "boundary_name": boundary_name,
            "crs": "EPSG:31370",
            "source_polygon_features": len(source_features),
            "output_polygon_features": len(output_features),
            "source_area_m2": source_area,
            "clipped_area_m2": clipped_area,
            "retained_area_percent": round((clipped_area / source_area * 100.0) if source_area else 0.0, 4),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Clip EPSG:31370 subzone polygons to an official EPSG:31370 ownership boundary")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--boundary", type=Path, required=True)
    parser.add_argument("--source-name", required=True)
    parser.add_argument("--boundary-name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    output = clip_collections(
        load_collection(args.source),
        load_collection(args.boundary),
        args.source_name,
        args.boundary_name,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    stats = output["grand_bruxelles_clip"]
    print(
        f"{args.source_name}: {stats['output_polygon_features']} clipped feature(s), "
        f"{stats['clipped_area_m2']:.1f} m2 retained ({stats['retained_area_percent']}%) -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
