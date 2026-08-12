#!/usr/bin/env python3
"""Extract one UrbIS 3D context building, preserving all solids linked to its stable 2D ID.

Unlike the hero extractor, context buildings may legitimately map to multiple BuildingSolids.
This wrapper aggregates every linked solid and all of its BuildingFaces instead of guessing one.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
HERO_PATH = HERE / "extract_urbis_3d_hero.py"
spec = importlib.util.spec_from_file_location("urbis_hero", HERO_PATH)
hero = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = hero
spec.loader.exec_module(hero)


def extract(args: argparse.Namespace) -> dict[str, Any]:
    root: Path = args.source_root
    prefix = root / args.prefix
    faces_shp = prefix.with_name(prefix.name + "_BuildingFaces.shp")
    faces_shx = prefix.with_name(prefix.name + "_BuildingFaces.shx")
    faces_dbf = prefix.with_name(prefix.name + "_BuildingFaces.dbf")
    solids_shp = prefix.with_name(prefix.name + "_BuildingSolids.shp")
    solids_dbf = prefix.with_name(prefix.name + "_BuildingSolids.dbf")

    solid_matches = hero.find_dbf_records(solids_dbf, "BU_ID", args.building_id)
    if not solid_matches:
        raise ValueError(f"No BuildingSolids found for {args.building_id}")

    raw_faces: list[dict[str, Any]] = []
    all_x: list[float] = []
    all_y: list[float] = []
    all_z: list[float] = []
    part_type_counts: dict[str, int] = {}
    solid_ids: list[str] = []
    solid_detail_levels: list[int | None] = []

    for _solid_index, solid_row in solid_matches:
        solid_id = solid_row["INSPIRE_ID"]
        solid_ids.append(solid_id)
        solid_detail_levels.append(hero.optional_int(solid_row["DETAILSLEV"]))
        face_matches = hero.find_dbf_records(faces_dbf, "BUSOLID_ID", solid_id)
        if not face_matches:
            raise ValueError(f"No BuildingFaces refer to solid {solid_id}")
        for face_index, face_row in face_matches:
            patch = hero.read_multipatch(faces_shp, faces_shx, face_index)
            triangles = hero.multipatch_triangles(patch)
            all_x.extend(point[0] for triangle in triangles for point in triangle)
            all_y.extend(point[1] for triangle in triangles for point in triangle)
            all_z.extend(point[2] for triangle in triangles for point in triangle)
            for part_type in patch["part_types"]:
                key = str(part_type)
                part_type_counts[key] = part_type_counts.get(key, 0) + 1
            raw_faces.append({
                "id": face_row["INSPIRE_ID"],
                "solid_id": solid_id,
                "type": face_row["TYPE"],
                "details_level": hero.optional_int(face_row["DETAILSLEV"]),
                "triangles": triangles,
            })

    if not all_z or not all(math.isfinite(value) for value in all_z):
        raise ValueError("UrbIS context building contains no finite Z coordinates")

    ground_z_values = [
        point[2]
        for face in raw_faces
        if face["type"] == "GROUNDSURFACE"
        for triangle in face["triangles"]
        for point in triangle
    ]
    base_z = min(ground_z_values) if ground_z_values else min(all_z)

    faces = []
    for face in raw_faces:
        faces.append({
            "id": face["id"],
            "solid_id": face["solid_id"],
            "type": face["type"],
            "details_level": face["details_level"],
            "triangles": [
                [hero.transform_point(point, args.origin_e, args.origin_n, args.world_x, args.world_z, base_z) for point in triangle]
                for triangle in face["triangles"]
            ],
        })

    type_counts: dict[str, int] = {}
    triangle_count = 0
    for face in faces:
        type_counts[face["type"]] = type_counts.get(face["type"], 0) + 1
        triangle_count += len(face["triangles"])

    uniform_detail = solid_detail_levels[0] if all(level == solid_detail_levels[0] for level in solid_detail_levels) else None
    return {
        "schema": "grand-bruxelles-urbis-context-mesh-v1",
        "context_id": args.context_id,
        "name": args.name,
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS - 3D Constructions",
            "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
            "dataset_url": "https://datastore.brussels/web/data/dataset/e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
            "package_url": args.package_url,
            "package_sha256": args.package_sha256.lower(),
            "building_faces_shp_sha256": hero.sha256_file(faces_shp),
            "building_solids_shp_sha256": hero.sha256_file(solids_shp),
            "package_revision": args.package_revision,
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/legalcode",
            "crs": "EPSG:31370",
            "accessed_at": args.accessed_at,
            "building_2d_id": args.building_id,
            "building_solid_ids": solid_ids,
            "solid_count": len(solid_ids),
            "details_level": uniform_detail,
        },
        "transform": {
            "lambert72_origin": [args.origin_e, args.origin_n],
            "world_origin": [args.world_x, 0.0, args.world_z],
            "source_base_z": round(base_z, 4),
        },
        "evidence": {
            "source_bbox_xy": [round(min(all_x), 4), round(min(all_y), 4), round(max(all_x), 4), round(max(all_y), 4)],
            "source_z_min": round(min(all_z), 4),
            "source_z_max": round(max(all_z), 4),
            "height_m": round(max(all_z) - base_z, 4),
            "solid_count": len(solid_ids),
            "face_count": len(faces),
            "face_type_counts": type_counts,
            "triangle_count": triangle_count,
            "multipatch_part_type_counts": part_type_counts,
        },
        "runtime_approved": False,
        "approval_note": "Authoritative CC0 LoD2 context evidence; runtime/photo-match/performance approval remains required.",
        "faces": faces,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--prefix", default="UrbISBuildings3D_148170")
    parser.add_argument("--building-id", required=True)
    parser.add_argument("--context-id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--package-url", required=True)
    parser.add_argument("--package-sha256", required=True)
    parser.add_argument("--package-revision", required=True)
    parser.add_argument("--accessed-at", required=True)
    parser.add_argument("--origin-e", type=float, required=True)
    parser.add_argument("--origin-n", type=float, required=True)
    parser.add_argument("--world-x", type=float, required=True)
    parser.add_argument("--world-z", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = extract(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print("URBIS_CONTEXT_EXTRACT:", result["context_id"], "solids=", result["evidence"]["solid_count"], "faces=", result["evidence"]["face_count"], "triangles=", result["evidence"]["triangle_count"], "height_m=", result["evidence"]["height_m"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
