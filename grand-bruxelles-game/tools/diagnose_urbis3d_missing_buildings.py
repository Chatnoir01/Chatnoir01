#!/usr/bin/env python3
"""Read-only spatial diagnostic for UrbIS2D buildings missing secondary UrbIS3D evidence.

This tool measures spatial overlap and nearest GROUNDSURFACE distance for explicitly
selected 2D building probes. It never creates a 3D->2D identity, never changes the
production matcher thresholds, and never authorizes runtime use.
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from osgeo import ogr

SCHEMA = "grand-bruxelles-urbis3d-missing-building-spatial-diagnostic-v1"
GROUND = "GROUNDSURFACE"


def normalize_field_name(value: str) -> str:
    return "".join(ch for ch in value.casefold() if ch.isalnum())


def resolve_field_name(layer: ogr.Layer, expected: str) -> str:
    wanted = normalize_field_name(expected)
    definition = layer.GetLayerDefn()
    for index in range(definition.GetFieldCount()):
        name = definition.GetFieldDefn(index).GetName()
        if normalize_field_name(name) == wanted:
            return name
    raise RuntimeError(f"Layer {layer.GetName()} missing required field {expected}")


def tail(value: str) -> str:
    return value.rstrip("/").rsplit("/", 1)[-1]


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


def find_buildingfaces(root: Path) -> tuple[ogr.DataSource, ogr.Layer, Path]:
    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        layer = dataset.GetLayerByName("BuildingFaces")
        if layer is not None:
            return dataset, layer, path
    raise RuntimeError("No BuildingFaces layer found")


def load_probes(
    path: Path,
    probe_ids: list[str],
    bbox: tuple[float, float, float, float],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    minx, miny, maxx, maxy = bbox
    if maxx <= minx or maxy <= miny:
        raise ValueError("invalid EPSG:31370 bbox")
    if not probe_ids:
        raise ValueError("at least one probe id is required")
    if len(probe_ids) != len(set(probe_ids)):
        raise ValueError("duplicate probe id")

    wanted = set(probe_ids)
    found: dict[str, dict[str, Any]] = {}
    for feature in payload.get("features", []):
        props = feature.get("properties") or {}
        inspire_id = props.get("INSPIRE_ID")
        geometry_json = feature.get("geometry")
        if not inspire_id or not geometry_json:
            continue
        probe_id = tail(str(inspire_id))
        if probe_id not in wanted:
            continue
        geometry = ogr.CreateGeometryFromJson(json.dumps(geometry_json))
        if geometry is None:
            raise ValueError(f"invalid geometry for probe {probe_id}")
        geometry = flatten_2d(geometry)
        envelope = geometry.GetEnvelope()
        if envelope[1] < minx or envelope[0] > maxx or envelope[3] < miny or envelope[2] > maxy:
            raise ValueError(f"probe outside target bbox: {probe_id}")
        found[probe_id] = {
            "probe_id": probe_id,
            "building_id": str(inspire_id),
            "block_id": props.get("BLOCK_ID"),
            "declared_area_m2": props.get("AREA"),
            "geometry": geometry,
            "geometry_area_m2": float(geometry.GetArea()),
        }

    missing = [probe for probe in probe_ids if probe not in found]
    if missing:
        raise ValueError("probe ids missing from 2D source: " + ",".join(missing))
    return [found[probe] for probe in probe_ids], {
        "timestamp": payload.get("timeStamp"),
        "number_returned": payload.get("numberReturned"),
        "total_features": payload.get("totalFeatures"),
    }


def collect_ground_solids(
    layer: ogr.Layer,
    bbox: tuple[float, float, float, float],
) -> dict[str, dict[str, Any]]:
    minx, miny, maxx, maxy = bbox
    if maxx <= minx or maxy <= miny:
        raise ValueError("invalid EPSG:31370 bbox")

    solid_field = resolve_field_name(layer, "BUSOLID_ID")
    type_field = resolve_field_name(layer, "TYPE")
    begin_field = resolve_field_name(layer, "BEGINLIFE")
    end_field = resolve_field_name(layer, "ENDLIFE")
    detail_field = resolve_field_name(layer, "DETAILSLEVEL")

    layer.SetSpatialFilterRect(minx, miny, maxx, maxy)
    records: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "ground_geometries": [],
        "ground_faces": 0,
        "begin_life": set(),
        "end_life": set(),
        "details_level": set(),
    })
    for feature in layer:
        solid_raw = feature.GetField(solid_field)
        type_raw = feature.GetField(type_field)
        geometry = feature.GetGeometryRef()
        if solid_raw is None or geometry is None:
            continue
        solid_id = str(solid_raw).strip()
        face_type = "" if type_raw is None else str(type_raw).strip()
        if not solid_id or face_type != GROUND:
            continue
        record = records[solid_id]
        record["ground_faces"] += 1
        record["ground_geometries"].append(geometry.Clone())
        for field, key in ((begin_field, "begin_life"), (end_field, "end_life"), (detail_field, "details_level")):
            value = feature.GetField(field)
            if value is not None and str(value).strip():
                record[key].add(str(value).strip())
    layer.SetSpatialFilter(None)
    layer.ResetReading()

    result: dict[str, dict[str, Any]] = {}
    for solid_id, record in records.items():
        ground = union_geometries(record["ground_geometries"])
        if ground is None or ground.IsEmpty():
            continue
        result[solid_id] = {
            "ground": ground,
            "ground_faces": record["ground_faces"],
            "begin_life": sorted(record["begin_life"]),
            "end_life": sorted(record["end_life"]),
            "details_level": sorted(record["details_level"]),
        }
    return result


def overlap_measure(ground: ogr.Geometry, building: ogr.Geometry) -> dict[str, float] | None:
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
        "symmetric_score": min(ground_coverage, building_coverage),
    }


def diagnose_probe(probe: dict[str, Any], solids: dict[str, dict[str, Any]]) -> dict[str, Any]:
    building = probe["geometry"]
    overlaps = []
    nearest = []
    for solid_id, record in solids.items():
        ground = record["ground"]
        distance = float(building.Distance(ground))
        nearest.append((distance, solid_id, record))
        measured = overlap_measure(ground, building)
        if measured is None:
            continue
        overlaps.append({
            "busolid_id": solid_id,
            **measured,
            "ground_faces": record["ground_faces"],
            "begin_life": record["begin_life"],
            "end_life": record["end_life"],
            "details_level": record["details_level"],
        })

    overlaps.sort(key=lambda item: (-item["symmetric_score"], item["busolid_id"]))
    nearest.sort(key=lambda item: (item[0], item[1]))
    nearest_item = None
    if nearest:
        distance, solid_id, record = nearest[0]
        nearest_item = {
            "busolid_id": solid_id,
            "distance_m": distance,
            "ground_faces": record["ground_faces"],
            "begin_life": record["begin_life"],
            "end_life": record["end_life"],
            "details_level": record["details_level"],
        }

    return {
        "probe_id": probe["probe_id"],
        "building_id": probe["building_id"],
        "block_id": probe["block_id"],
        "declared_area_m2": probe["declared_area_m2"],
        "geometry_area_m2": probe["geometry_area_m2"],
        "intersecting_groundsolid_count": len(overlaps),
        "spatial_observation": "groundsurface_overlap_present" if overlaps else "no_groundsurface_overlap_in_snapshot",
        "best_overlap": overlaps[0] if overlaps else None,
        "nearest_groundsolid": nearest_item,
        "top_overlaps": overlaps[:5],
        "identity_authorized": False,
        "runtime_approved": False,
    }


def build_report(
    probes: list[dict[str, Any]],
    solids: dict[str, dict[str, Any]],
    bbox: tuple[float, float, float, float],
    *,
    source_2d: dict[str, Any],
    package_date: str | None,
) -> dict[str, Any]:
    rows = [diagnose_probe(probe, solids) for probe in probes]
    return {
        "schema": SCHEMA,
        "bbox_epsg31370": list(bbox),
        "source_2d": source_2d,
        "source_3d": {"embedded_date": package_date, "ground_solids_in_bbox": len(solids)},
        "policy": {
            "crs": "EPSG:31370",
            "read_only": True,
            "spatial_diagnostic_only": True,
            "identity_authorization": False,
            "runtime_approval": False,
            "thresholds_changed": False,
            "interpretation": "overlap and distance are observations only; they do not authorize a 3D->2D identity",
        },
        "counts": {
            "probe_count": len(rows),
            "probes_with_groundsurface_overlap": sum(1 for row in rows if row["intersecting_groundsolid_count"] > 0),
            "probes_without_groundsurface_overlap": sum(1 for row in rows if row["intersecting_groundsolid_count"] == 0),
        },
        "probes": rows,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bbox", type=float, nargs=4, required=True)
    parser.add_argument("--probe-id", action="append", default=[])
    parser.add_argument("--package-date")
    return parser.parse_args()


def main() -> int:
    ogr.UseExceptions()
    args = parse_args()
    bbox = tuple(args.bbox)
    probes, source_2d = load_probes(args.buildings, list(args.probe_id), bbox)
    dataset, layer, package = find_buildingfaces(args.root)
    solids = collect_ground_solids(layer, bbox)
    report = build_report(
        probes,
        solids,
        bbox,
        source_2d=source_2d,
        package_date=args.package_date,
    )
    report["source_3d"]["package_path"] = str(package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "URBIS3D_MISSING_BUILDING_SPATIAL_DIAGNOSTIC",
        f"probes={report['counts']['probe_count']}",
        f"overlap={report['counts']['probes_with_groundsurface_overlap']}",
        f"no_overlap={report['counts']['probes_without_groundsurface_overlap']}",
        "identity_authorized=false",
        "runtime_approved=false",
    )
    dataset = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
