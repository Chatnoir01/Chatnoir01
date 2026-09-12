#!/usr/bin/env python3
"""Build a deterministic, source-faithful UrbIS 3D slice for Atomium / Heysel.

The official SHP distribution stores building faces as MultiPatch records. This
builder reuses the repository's audited MultiPatch parser, joins each face back
to its BuildingSolid and stable 2D building id, filters on the exact official
Atomium DTM envelope, and keeps source Z as absolute UrbIS elevation.

No game-Y conversion, height inference, clipping, or geometry synthesis happens
here. Runtime vertical binding remains a separate reviewed step.
"""
from __future__ import annotations

import argparse
import hashlib
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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def intersects(bbox: list[float], bounds: tuple[float, float, float, float]) -> bool:
    min_x, min_y, max_x, max_y = bbox
    bmin_x, bmin_y, bmax_x, bmax_y = bounds
    return max_x >= bmin_x and min_x <= bmax_x and max_y >= bmin_y and min_y <= bmax_y


def compact_number(value: float) -> float:
    return round(float(value), 4)


def game_point(point: list[float], origin_e: float, origin_n: float) -> list[float]:
    e, n, absolute_z = point
    return [compact_number(e - origin_e), compact_number(absolute_z), compact_number(origin_n - n)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--min-e", type=float, required=True)
    parser.add_argument("--min-n", type=float, required=True)
    parser.add_argument("--max-e", type=float, required=True)
    parser.add_argument("--max-n", type=float, required=True)
    parser.add_argument("--origin-e", type=float, required=True)
    parser.add_argument("--origin-n", type=float, required=True)
    parser.add_argument("--package-url", required=True)
    parser.add_argument("--package-sha256", required=True)
    parser.add_argument("--distribution-date", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    prefix = args.source_root / args.prefix
    faces_shp = prefix.with_name(prefix.name + "_BuildingFaces.shp")
    faces_shx = prefix.with_name(prefix.name + "_BuildingFaces.shx")
    faces_dbf = prefix.with_name(prefix.name + "_BuildingFaces.dbf")
    solids_shp = prefix.with_name(prefix.name + "_BuildingSolids.shp")
    solids_dbf = prefix.with_name(prefix.name + "_BuildingSolids.dbf")
    required = [faces_shp, faces_shx, faces_dbf, solids_shp, solids_dbf]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing official UrbIS 3D inputs: " + ", ".join(missing))

    bounds = (args.min_e, args.min_n, args.max_e, args.max_n)
    if not all(math.isfinite(value) for value in bounds) or args.max_e <= args.min_e or args.max_n <= args.min_n:
        raise SystemExit("Invalid DTM source bounds")

    solid_to_building: dict[str, dict[str, Any]] = {}
    for _index, row in hero.read_dbf(solids_dbf):
        solid_id = row.get("INSPIRE_ID", "")
        building_id = row.get("BU_ID", "")
        if not solid_id or not building_id:
            continue
        solid_to_building[solid_id] = {
            "building_id": building_id,
            "details_level": hero.optional_int(row.get("DETAILSLEV", "")),
        }

    faces: list[dict[str, Any]] = []
    source_building_ids: set[str] = set()
    source_solid_ids: set[str] = set()
    type_counts: dict[str, int] = {}
    triangle_count = 0
    source_z_min = math.inf
    source_z_max = -math.inf
    unmatched_solid_faces = 0

    for face_index, row in hero.read_dbf(faces_dbf):
        patch = hero.read_multipatch(faces_shp, faces_shx, face_index)
        if not intersects(patch["bbox_xy"], bounds):
            continue
        solid_id = row.get("BUSOLID_ID", "")
        solid = solid_to_building.get(solid_id)
        if solid is None:
            unmatched_solid_faces += 1
            continue
        triangles = hero.multipatch_triangles(patch)
        if not triangles:
            continue
        transformed: list[list[list[float]]] = []
        for triangle in triangles:
            converted = [game_point(point, args.origin_e, args.origin_n) for point in triangle]
            transformed.append(converted)
            for point in triangle:
                source_z_min = min(source_z_min, float(point[2]))
                source_z_max = max(source_z_max, float(point[2]))
        face_type = row.get("TYPE", "") or "UNCLASSIFIED"
        building_id = str(solid["building_id"])
        source_building_ids.add(building_id)
        source_solid_ids.add(solid_id)
        type_counts[face_type] = type_counts.get(face_type, 0) + 1
        triangle_count += len(transformed)
        faces.append({
            "id": row.get("INSPIRE_ID", ""),
            "solid_id": solid_id,
            "building_id": building_id,
            "type": face_type,
            "details_level": hero.optional_int(row.get("DETAILSLEV", "")),
            "triangles_x_absz_z": transformed,
        })

    if not faces or triangle_count <= 0 or not math.isfinite(source_z_min) or not math.isfinite(source_z_max):
        raise SystemExit("No source-backed UrbIS 3D faces intersect the Atomium DTM envelope")

    faces.sort(key=lambda face: (face["building_id"], face["solid_id"], face["type"], face["id"]))
    result = {
        "schema": "grand-bruxelles-atomium-heysel-urbis3d-slice-v1",
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS - Constructions 3D",
            "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
            "license": "CC0-1.0",
            "crs": "EPSG:31370",
            "tile": "148176",
            "distribution_date": args.distribution_date,
            "package_url": args.package_url,
            "package_sha256": args.package_sha256.lower(),
            "building_faces_shp_sha256": sha256_file(faces_shp),
            "building_solids_shp_sha256": sha256_file(solids_shp),
        },
        "filter": {
            "dtm_bounds_epsg31370": [compact_number(value) for value in bounds],
            "game_origin_e": args.origin_e,
            "game_origin_n": args.origin_n,
            "intersection_rule": "source_face_bbox_intersects_exact_dtm_bounds_inclusive",
        },
        "coordinates": {
            "triangle_order": ["game_x", "source_absolute_z_m", "game_z"],
            "game_x": "source_easting - game_origin_e",
            "game_z": "game_origin_n - source_northing",
            "vertical_policy": "absolute_source_z_preserved_unconverted",
            "game_y_conversion_claimed": False,
        },
        "evidence": {
            "building_count": len(source_building_ids),
            "solid_count": len(source_solid_ids),
            "face_count": len(faces),
            "face_type_counts": dict(sorted(type_counts.items())),
            "triangle_count": triangle_count,
            "source_z_min_m": compact_number(source_z_min),
            "source_z_max_m": compact_number(source_z_max),
            "unmatched_solid_faces": unmatched_solid_faces,
        },
        "runtime_approved": False,
        "visual_approved": False,
        "jouable_claim": False,
        "faces": faces,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(
        "ATOMIUM_HEYSEL_URBIS3D_SLICE_OK "
        f"buildings={result['evidence']['building_count']} solids={result['evidence']['solid_count']} "
        f"faces={result['evidence']['face_count']} triangles={triangle_count} "
        f"z={result['evidence']['source_z_min_m']}..{result['evidence']['source_z_max_m']} "
        "game_y_conversion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
