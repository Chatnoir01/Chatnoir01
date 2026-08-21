#!/usr/bin/env python3
"""Read-only diagnostic for UrbIS3D BuildingFaces identity fields.

This tool does not authorize matching or runtime use. It only measures whether
BuildingFaces.INSPIRE_ID or BUSOLID_ID values are *exactly equal* to current
UrbIS 2D building INSPIRE_ID values inside one EPSG:31370 cell.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from osgeo import ogr


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


def find_buildingfaces(root: Path) -> tuple[ogr.DataSource, ogr.Layer, Path]:
    observed: list[str] = []
    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        observed.extend(dataset.GetLayerByIndex(i).GetName() for i in range(dataset.GetLayerCount()))
        layer = dataset.GetLayerByName("BuildingFaces")
        if layer is not None:
            return dataset, layer, path
    raise RuntimeError(f"No BuildingFaces layer found; observed_layers={sorted(set(observed))}")


def load_2d_building_ids(path: Path) -> set[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    result: set[str] = set()
    for feature in payload.get("features", []):
        props = feature.get("properties") or {}
        value = props.get("INSPIRE_ID")
        if value is not None and str(value).strip():
            result.add(str(value).strip())
    if not result:
        raise ValueError("2D building source contains no INSPIRE_ID")
    return result


def tail(value: str) -> str:
    return value.rstrip("/").rsplit("/", 1)[-1]


def diagnose(
    layer: ogr.Layer,
    building_ids: set[str],
    bbox: tuple[float, float, float, float],
    probe_ids: list[str],
) -> dict[str, Any]:
    minx, miny, maxx, maxy = bbox
    if maxx <= minx or maxy <= miny:
        raise ValueError("invalid EPSG:31370 bbox")

    inspire_field = resolve_field_name(layer, "INSPIRE_ID")
    solid_field = resolve_field_name(layer, "BUSOLID_ID")
    type_field = resolve_field_name(layer, "TYPE")

    layer.SetSpatialFilterRect(minx, miny, maxx, maxy)
    face_inspire_values: set[str] = set()
    busolid_values: set[str] = set()
    face_types: Counter[str] = Counter()
    faces_per_solid: Counter[str] = Counter()
    inspire_per_solid: dict[str, set[str]] = defaultdict(set)
    exact_face_matches: Counter[str] = Counter()
    exact_solid_matches: Counter[str] = Counter()
    face_count = 0

    for feature in layer:
        face_count += 1
        face_inspire = feature.GetField(inspire_field)
        busolid = feature.GetField(solid_field)
        face_type = feature.GetField(type_field)
        face_inspire = "" if face_inspire is None else str(face_inspire).strip()
        busolid = "" if busolid is None else str(busolid).strip()
        face_type = "" if face_type is None else str(face_type).strip()

        if face_inspire:
            face_inspire_values.add(face_inspire)
            if face_inspire in building_ids:
                exact_face_matches[face_inspire] += 1
        if busolid:
            busolid_values.add(busolid)
            faces_per_solid[busolid] += 1
            if busolid in building_ids:
                exact_solid_matches[busolid] += 1
            if face_inspire:
                inspire_per_solid[busolid].add(face_inspire)
        if face_type:
            face_types[face_type] += 1

    layer.SetSpatialFilter(None)

    building_tail_map = {tail(value): value for value in building_ids}
    face_tail_map = {tail(value): value for value in face_inspire_values}
    solid_tail_map = {tail(value): value for value in busolid_values}
    probe_report = []
    for probe in probe_ids:
        full = building_tail_map.get(probe)
        probe_report.append({
            "probe_id": probe,
            "building_2d_in_cell": full is not None,
            "building_2d_inspire_id": full,
            "exact_buildingfaces_inspire_match": bool(full and full in face_inspire_values),
            "exact_busolid_match": bool(full and full in busolid_values),
            "same_tail_buildingfaces_inspire": face_tail_map.get(probe),
            "same_tail_busolid": solid_tail_map.get(probe),
        })

    uniform_solids = sum(1 for values in inspire_per_solid.values() if len(values) == 1)
    multi_inspire_solids = sum(1 for values in inspire_per_solid.values() if len(values) > 1)
    exact_face_ids = set(exact_face_matches)
    exact_solid_ids = set(exact_solid_matches)

    return {
        "schema": "grand-bruxelles-urbis3d-buildingfaces-identity-diagnostic-v1",
        "bbox_epsg31370": list(bbox),
        "policy": {
            "read_only": True,
            "identity_authorization": False,
            "runtime_approval": False,
            "comparison": "exact string equality only; tail equality reported as diagnostic, never authorization",
        },
        "counts": {
            "building_2d_ids": len(building_ids),
            "building_faces_in_bbox": face_count,
            "unique_buildingfaces_inspire_ids": len(face_inspire_values),
            "unique_busolid_ids": len(busolid_values),
            "exact_face_inspire_to_2d_ids": len(exact_face_ids),
            "exact_busolid_to_2d_ids": len(exact_solid_ids),
            "busolids_with_one_face_inspire_id": uniform_solids,
            "busolids_with_multiple_face_inspire_ids": multi_inspire_solids,
        },
        "face_types": dict(sorted(face_types.items())),
        "exact_face_inspire_matches": sorted(exact_face_ids),
        "exact_busolid_matches": sorted(exact_solid_ids),
        "probes": probe_report,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--buildings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bbox", type=float, nargs=4, required=True)
    parser.add_argument("--probe-id", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    ogr.UseExceptions()
    args = parse_args()
    bbox = tuple(args.bbox)
    building_ids = load_2d_building_ids(args.buildings)
    dataset, layer, package = find_buildingfaces(args.root)
    report = diagnose(layer, building_ids, bbox, list(args.probe_id))
    report["source_package_path"] = str(package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = report["counts"]
    print(
        "URBIS3D_FACE_IDENTITY_DIAGNOSTIC",
        f"buildings2d={counts['building_2d_ids']}",
        f"faces={counts['building_faces_in_bbox']}",
        f"face_ids={counts['unique_buildingfaces_inspire_ids']}",
        f"solids={counts['unique_busolid_ids']}",
        f"exact_face_to_2d={counts['exact_face_inspire_to_2d_ids']}",
        f"exact_solid_to_2d={counts['exact_busolid_to_2d_ids']}",
        "identity_authorized=false runtime_approved=false",
    )
    for probe in report["probes"]:
        print("URBIS3D_FACE_IDENTITY_PROBE", json.dumps(probe, sort_keys=True))
    dataset = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
