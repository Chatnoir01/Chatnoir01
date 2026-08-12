#!/usr/bin/env python3
"""Build read-only per-building UrbIS 3D semantic height evidence for one Ixelles seed cell.

The tool intentionally keeps 2D building INSPIRE_ID and 3D BUSOLID_ID separate. It
matches them spatially using semantically tagged GROUNDSURFACE polygons, and derives
height evidence only from ROOFSURFACE versus GROUNDSURFACE Z samples. It never
approves runtime height values.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from osgeo import ogr

SCHEMA = "grand-bruxelles-ixelles-urbis3d-semantic-match-v1"
ROOF = "ROOFSURFACE"
GROUND = "GROUNDSURFACE"
DEFAULT_BBOX = (149000.0, 169000.0, 149500.0, 169500.0)
MIN_MATCH_SCORE = 0.70
MIN_RUNNER_UP_MARGIN = 0.15
MIN_HEIGHT_M = 2.0
MAX_HEIGHT_M = 100.0


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = (len(ordered) - 1) * p
    lo, hi = math.floor(pos), math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def iter_points(geometry: ogr.Geometry) -> Iterable[tuple[float, float, float]]:
    count = geometry.GetGeometryCount()
    if count:
        for index in range(count):
            child = geometry.GetGeometryRef(index)
            if child is not None:
                yield from iter_points(child)
        return
    for index in range(geometry.GetPointCount()):
        point = geometry.GetPoint(index)
        if len(point) >= 3:
            yield float(point[0]), float(point[1]), float(point[2])


def flatten_2d(geometry: ogr.Geometry) -> ogr.Geometry:
    clone = geometry.Clone()
    clone.FlattenTo2D()
    return clone


def union_geometries(geometries: list[ogr.Geometry]) -> ogr.Geometry | None:
    if not geometries:
        return None
    result = flatten_2d(geometries[0])
    for geometry in geometries[1:]:
        merged = result.Union(flatten_2d(geometry))
        if merged is not None and not merged.IsEmpty():
            result = merged
    return result


def envelopes_intersect(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    # OGR envelope order: minX, maxX, minY, maxY.
    return not (a[1] < b[0] or b[1] < a[0] or a[3] < b[2] or b[3] < a[2])


def load_buildings(path: Path, bbox: tuple[float, float, float, float]) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    minx, miny, maxx, maxy = bbox
    buildings = []
    for feature in payload.get("features", []):
        props = feature.get("properties") or {}
        inspire_id = props.get("INSPIRE_ID")
        geometry_json = feature.get("geometry")
        if not inspire_id or not geometry_json:
            continue
        geometry = ogr.CreateGeometryFromJson(json.dumps(geometry_json))
        if geometry is None:
            continue
        envelope = geometry.GetEnvelope()
        if envelope[1] < minx or envelope[0] > maxx or envelope[3] < miny or envelope[2] > maxy:
            continue
        buildings.append({
            "inspire_id": str(inspire_id),
            "area_declared_m2": props.get("AREA"),
            "geometry": geometry,
            "envelope": envelope,
            "area_m2": float(geometry.GetArea()),
        })
    return buildings


def find_buildingfaces(root: Path) -> tuple[ogr.DataSource, ogr.Layer, Path]:
    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        layer = dataset.GetLayerByName("BuildingFaces")
        if layer is not None:
            return dataset, layer, path
    raise RuntimeError("No BuildingFaces layer found")


def collect_solids(layer: ogr.Layer, bbox: tuple[float, float, float, float]) -> dict[str, dict[str, Any]]:
    minx, miny, maxx, maxy = bbox
    layer.SetSpatialFilterRect(minx, miny, maxx, maxy)
    solids: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "ground_geometries": [], "roof_geometries": [], "ground_z": [], "roof_z": [],
        "ground_faces": 0, "roof_faces": 0,
    })
    for feature in layer:
        solid_id = feature.GetField("BUSOLID_ID")
        face_type = feature.GetField("TYPE")
        geometry = feature.GetGeometryRef()
        if not solid_id or face_type not in (GROUND, ROOF) or geometry is None:
            continue
        record = solids[str(solid_id)]
        samples = [z for _x, _y, z in iter_points(geometry) if math.isfinite(z)]
        if face_type == GROUND:
            record["ground_faces"] += 1
            record["ground_z"].extend(samples)
            record["ground_geometries"].append(geometry.Clone())
        else:
            record["roof_faces"] += 1
            record["roof_z"].extend(samples)
            record["roof_geometries"].append(geometry.Clone())
    layer.SetSpatialFilter(None)
    return dict(solids)


def score_match(ground: ogr.Geometry, building: ogr.Geometry) -> dict[str, float] | None:
    intersection = ground.Intersection(building)
    if intersection is None or intersection.IsEmpty() or intersection.GetDimension() < 2:
        return None
    intersection_area = float(intersection.GetArea())
    ground_area = float(ground.GetArea())
    building_area = float(building.GetArea())
    if intersection_area <= 0 or ground_area <= 0 or building_area <= 0:
        return None
    ground_coverage = intersection_area / ground_area
    building_coverage = intersection_area / building_area
    return {
        "intersection_area_m2": intersection_area,
        "ground_coverage": ground_coverage,
        "building_coverage": building_coverage,
        "score": min(ground_coverage, building_coverage),
    }


def build_evidence(buildings: list[dict[str, Any]], solids: dict[str, dict[str, Any]], bbox: tuple[float, float, float, float]) -> dict[str, Any]:
    matches = []
    counters = defaultdict(int)
    for solid_id in sorted(solids):
        solid = solids[solid_id]
        ground = union_geometries(solid["ground_geometries"])
        roof_z = solid["roof_z"]
        ground_z = solid["ground_z"]
        if ground is None or ground.IsEmpty():
            counters["no_ground_geometry"] += 1
            continue
        candidates = []
        ground_envelope = ground.GetEnvelope()
        for building in buildings:
            if not envelopes_intersect(ground_envelope, building["envelope"]):
                continue
            scored = score_match(ground, building["geometry"])
            if scored:
                candidates.append({"inspire_id": building["inspire_id"], **scored})
        candidates.sort(key=lambda item: (-item["score"], item["inspire_id"]))
        best = candidates[0] if candidates else None
        runner = candidates[1] if len(candidates) > 1 else None
        margin = (best["score"] - runner["score"]) if best and runner else (best["score"] if best else 0.0)
        unique_match = bool(best and best["score"] >= MIN_MATCH_SCORE and margin >= MIN_RUNNER_UP_MARGIN)

        ground_median = percentile(ground_z, 0.50)
        roof_median = percentile(roof_z, 0.50)
        height = None if ground_median is None or roof_median is None else roof_median - ground_median
        height_plausible = bool(height is not None and MIN_HEIGHT_M <= height <= MAX_HEIGHT_M)
        if not candidates:
            status = "unmatched"
        elif not unique_match:
            status = "ambiguous"
        elif not roof_z or not ground_z:
            status = "matched_missing_semantic_z"
        elif not height_plausible:
            status = "matched_implausible_height"
        else:
            status = "matched_semantic_evidence"
        counters[status] += 1
        matches.append({
            "busolid_id": solid_id,
            "status": status,
            "matched_inspire_id": best["inspire_id"] if unique_match and best else None,
            "match_score": None if best is None else best["score"],
            "runner_up_score": None if runner is None else runner["score"],
            "match_margin": margin,
            "ground_faces": solid["ground_faces"],
            "roof_faces": solid["roof_faces"],
            "ground_z_samples": len(ground_z),
            "roof_z_samples": len(roof_z),
            "ground_z_p25_m": percentile(ground_z, 0.25),
            "ground_z_median_m": ground_median,
            "ground_z_p75_m": percentile(ground_z, 0.75),
            "roof_z_p25_m": percentile(roof_z, 0.25),
            "roof_z_median_m": roof_median,
            "roof_z_p75_m": percentile(roof_z, 0.75),
            "semantic_height_m": height,
            "height_plausible": height_plausible,
            "runtime_approved": False,
        })
    semantic = [m for m in matches if m["status"] == "matched_semantic_evidence"]
    heights = [m["semantic_height_m"] for m in semantic if m["semantic_height_m"] is not None]
    return {
        "schema": SCHEMA,
        "cell": "bxl-e149000-n169000-s500",
        "bbox_epsg31370": list(bbox),
        "policy": {
            "crs": "EPSG:31370",
            "match_basis": "BUSOLID_ID GROUNDSURFACE 2D overlap against UrbIS 2D building footprint",
            "height_basis": "median ROOFSURFACE Z minus median GROUNDSURFACE Z",
            "min_match_score": MIN_MATCH_SCORE,
            "min_runner_up_margin": MIN_RUNNER_UP_MARGIN,
            "plausible_height_range_m": [MIN_HEIGHT_M, MAX_HEIGHT_M],
            "dsm_dtm_comparison_performed": False,
            "runtime_approval": False,
        },
        "counts": {
            "urbis_2d_buildings": len(buildings),
            "building_solids_in_bbox": len(solids),
            **dict(sorted(counters.items())),
        },
        "semantic_height_summary_m": {
            "count": len(heights),
            "min": min(heights) if heights else None,
            "median": statistics.median(heights) if heights else None,
            "p75": percentile(heights, 0.75),
            "max": max(heights) if heights else None,
        },
        "matches": matches,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bbox", type=float, nargs=4, default=DEFAULT_BBOX)
    return parser.parse_args()


def main() -> int:
    ogr.UseExceptions()
    args = parse_args()
    bbox = tuple(args.bbox)
    buildings = load_buildings(args.buildings, bbox)
    dataset, layer, package = find_buildingfaces(args.root)
    solids = collect_solids(layer, bbox)
    evidence = build_evidence(buildings, solids, bbox)
    evidence["source_package_path"] = str(package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = evidence["counts"]
    print("IXELLES_SEMANTIC_MATCH", "buildings=", counts["urbis_2d_buildings"], "solids=", counts["building_solids_in_bbox"], "semantic=", counts.get("matched_semantic_evidence", 0), "runtime_approved=false")
    dataset = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
