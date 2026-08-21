#!/usr/bin/env python3
"""Read-only diagnostic for UrbIS3D face/solid identity relations.

This tool never authorizes matching or runtime use. It measures, on one live
EPSG:31370 cell, whether the official chain

BuildingFaces.BUSOLID_ID -> BuildingSolids.inspire_Id -> BuildingSolids.bu2d_Id
-> UrbIS 2D building INSPIRE_ID

holds by exact string equality. BuildingFaces.INSPIRE_ID and raw BUSOLID_ID are
also compared directly with 2D IDs as negative/diagnostic controls.
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


def find_urbis3d_layers(root: Path) -> tuple[ogr.DataSource, ogr.Layer, ogr.Layer, Path]:
    observed: list[str] = []
    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        observed.extend(dataset.GetLayerByIndex(i).GetName() for i in range(dataset.GetLayerCount()))
        faces = dataset.GetLayerByName("BuildingFaces")
        solids = dataset.GetLayerByName("BuildingSolids")
        if faces is not None and solids is not None:
            return dataset, faces, solids, path
    raise RuntimeError(
        "No GeoPackage with both BuildingFaces and BuildingSolids found; "
        f"observed_layers={sorted(set(observed))}"
    )


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


def collect_faces(
    layer: ogr.Layer,
    building_ids: set[str],
    bbox: tuple[float, float, float, float],
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
    layer.ResetReading()
    return {
        "face_count": face_count,
        "face_inspire_values": face_inspire_values,
        "busolid_values": busolid_values,
        "face_types": face_types,
        "faces_per_solid": faces_per_solid,
        "inspire_per_solid": inspire_per_solid,
        "exact_face_matches": exact_face_matches,
        "exact_solid_matches": exact_solid_matches,
    }


def collect_solid_links(layer: ogr.Layer) -> dict[str, Any]:
    """Collect exact official solid identity links and expose conflicts fail-closed."""
    inspire_field = resolve_field_name(layer, "inspire_Id")
    building_field = resolve_field_name(layer, "bu2d_Id")
    links: dict[str, str] = {}
    conflicts: dict[str, set[str]] = defaultdict(set)
    solid_ids: set[str] = set()
    building_values: set[str] = set()
    rows = 0
    nonempty_links = 0

    layer.ResetReading()
    for feature in layer:
        rows += 1
        solid_raw = feature.GetField(inspire_field)
        building_raw = feature.GetField(building_field)
        solid_id = "" if solid_raw is None else str(solid_raw).strip()
        building_id = "" if building_raw is None else str(building_raw).strip()
        if solid_id:
            solid_ids.add(solid_id)
        if building_id:
            building_values.add(building_id)
        if not solid_id or not building_id:
            continue
        nonempty_links += 1
        previous = links.get(solid_id)
        if previous is None:
            links[solid_id] = building_id
        elif previous != building_id:
            conflicts[solid_id].update((previous, building_id))

    layer.ResetReading()
    for solid_id in conflicts:
        links.pop(solid_id, None)
    return {
        "row_count": rows,
        "solid_ids": solid_ids,
        "building_values": building_values,
        "nonempty_link_rows": nonempty_links,
        "links": links,
        "conflicts": conflicts,
    }


def diagnose(
    face_layer: ogr.Layer,
    solid_layer: ogr.Layer,
    building_ids: set[str],
    bbox: tuple[float, float, float, float],
    probe_ids: list[str],
) -> dict[str, Any]:
    faces = collect_faces(face_layer, building_ids, bbox)
    solids = collect_solid_links(solid_layer)

    face_inspire_values: set[str] = faces["face_inspire_values"]
    busolid_values: set[str] = faces["busolid_values"]
    solid_ids: set[str] = solids["solid_ids"]
    links: dict[str, str] = solids["links"]

    exact_face_ids = set(faces["exact_face_matches"])
    exact_solid_ids = set(faces["exact_solid_matches"])
    joined_busolids = busolid_values & solid_ids
    missing_busolids = busolid_values - solid_ids
    joined_with_unambiguous_link = {solid_id for solid_id in joined_busolids if solid_id in links}
    joined_without_link = joined_busolids - joined_with_unambiguous_link
    exact_official_2d = {
        links[solid_id]
        for solid_id in joined_with_unambiguous_link
        if links[solid_id] in building_ids
    }
    linked_to_missing_2d = {
        solid_id: links[solid_id]
        for solid_id in sorted(joined_with_unambiguous_link)
        if links[solid_id] not in building_ids
    }

    building_tail_map = {tail(value): value for value in building_ids}
    face_tail_map = {tail(value): value for value in face_inspire_values}
    raw_solid_tail_map = {tail(value): value for value in busolid_values}
    official_by_2d: dict[str, list[str]] = defaultdict(list)
    for solid_id in joined_with_unambiguous_link:
        official_by_2d[links[solid_id]].append(solid_id)

    probe_report = []
    for probe in probe_ids:
        full = building_tail_map.get(probe)
        official_solids = sorted(official_by_2d.get(full or "", []))
        probe_report.append({
            "probe_id": probe,
            "building_2d_in_cell": full is not None,
            "building_2d_inspire_id": full,
            "exact_buildingfaces_inspire_match": bool(full and full in face_inspire_values),
            "exact_busolid_match": bool(full and full in busolid_values),
            "same_tail_buildingfaces_inspire": face_tail_map.get(probe),
            "same_tail_busolid": raw_solid_tail_map.get(probe),
            "official_buildingsolids_via_bu2d": official_solids,
            "official_chain_match": bool(official_solids),
        })

    inspire_per_solid: dict[str, set[str]] = faces["inspire_per_solid"]
    uniform_solids = sum(1 for values in inspire_per_solid.values() if len(values) == 1)
    multi_inspire_solids = sum(1 for values in inspire_per_solid.values() if len(values) > 1)
    conflicts: dict[str, set[str]] = solids["conflicts"]

    return {
        "schema": "grand-bruxelles-urbis3d-building-identity-diagnostic-v2",
        "bbox_epsg31370": list(bbox),
        "policy": {
            "read_only": True,
            "identity_authorization": False,
            "runtime_approval": False,
            "comparison": "exact string equality only; tail equality reported as diagnostic, never authorization",
            "official_chain_under_test": "BuildingFaces.BUSOLID_ID -> BuildingSolids.inspire_Id -> BuildingSolids.bu2d_Id -> UrbIS2D.INSPIRE_ID",
        },
        "counts": {
            "building_2d_ids": len(building_ids),
            "building_faces_in_bbox": faces["face_count"],
            "unique_buildingfaces_inspire_ids": len(face_inspire_values),
            "unique_busolid_ids": len(busolid_values),
            "exact_face_inspire_to_2d_ids": len(exact_face_ids),
            "exact_busolid_to_2d_ids": len(exact_solid_ids),
            "busolids_with_one_face_inspire_id": uniform_solids,
            "busolids_with_multiple_face_inspire_ids": multi_inspire_solids,
            "building_solids_rows_package": solids["row_count"],
            "building_solids_unique_inspire_ids_package": len(solid_ids),
            "building_solids_nonempty_bu2d_rows_package": solids["nonempty_link_rows"],
            "building_solids_unique_bu2d_ids_package": len(solids["building_values"]),
            "building_solids_identity_conflicts_package": len(conflicts),
            "face_busolid_ids_joined_to_buildingsolids": len(joined_busolids),
            "face_busolid_ids_missing_buildingsolids": len(missing_busolids),
            "joined_solids_with_unambiguous_bu2d": len(joined_with_unambiguous_link),
            "joined_solids_without_unambiguous_bu2d": len(joined_without_link),
            "joined_bu2d_exact_2d_ids": len(exact_official_2d),
            "joined_solids_pointing_to_missing_2d_ids": len(linked_to_missing_2d),
        },
        "face_types": dict(sorted(faces["face_types"].items())),
        "exact_face_inspire_matches": sorted(exact_face_ids),
        "exact_busolid_matches": sorted(exact_solid_ids),
        "face_busolid_ids_missing_buildingsolids": sorted(missing_busolids),
        "joined_solids_without_unambiguous_bu2d": sorted(joined_without_link),
        "joined_solids_pointing_to_missing_2d_ids": linked_to_missing_2d,
        "building_solids_identity_conflicts": {
            key: sorted(values) for key, values in sorted(conflicts.items())
        },
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
    dataset, face_layer, solid_layer, package = find_urbis3d_layers(args.root)
    report = diagnose(face_layer, solid_layer, building_ids, bbox, list(args.probe_id))
    report["source_package_path"] = str(package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = report["counts"]
    print(
        "URBIS3D_FACE_IDENTITY_DIAGNOSTIC",
        f"buildings2d={counts['building_2d_ids']}",
        f"faces={counts['building_faces_in_bbox']}",
        f"face_ids={counts['unique_buildingfaces_inspire_ids']}",
        f"face_solids={counts['unique_busolid_ids']}",
        f"exact_face_to_2d={counts['exact_face_inspire_to_2d_ids']}",
        f"exact_raw_solid_to_2d={counts['exact_busolid_to_2d_ids']}",
        f"face_to_solid={counts['face_busolid_ids_joined_to_buildingsolids']}",
        f"face_to_solid_missing={counts['face_busolid_ids_missing_buildingsolids']}",
        f"solid_bu2d={counts['joined_solids_with_unambiguous_bu2d']}",
        f"bu2d_to_2d={counts['joined_bu2d_exact_2d_ids']}",
        f"bu2d_missing_2d={counts['joined_solids_pointing_to_missing_2d_ids']}",
        f"solid_conflicts={counts['building_solids_identity_conflicts_package']}",
        "identity_authorized=false runtime_approved=false",
    )
    for probe in report["probes"]:
        print("URBIS3D_FACE_IDENTITY_PROBE", json.dumps(probe, sort_keys=True))
    dataset = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
