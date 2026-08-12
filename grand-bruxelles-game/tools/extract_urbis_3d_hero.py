#!/usr/bin/env python3
"""Extract one audited UrbIS 3D building into a compact game mesh.

The official UrbIS Shapefile distribution stores LoD2 faces as MultiPatch
records.  This tool intentionally uses only the Python standard library: raw
source packages remain outside Git, and no GIS runtime dependency is added to
the game.  Selection is by the stable UrbIS 2D building identifier, never by a
nearest-feature guess.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Sequence


MULTIPATCH = 31
PART_TRIANGLE_STRIP = 0
PART_TRIANGLE_FAN = 1
PART_OUTER_RING = 2
PART_INNER_RING = 3
PART_FIRST_RING = 4
PART_RING = 5


@dataclass(frozen=True)
class DbfField:
    name: str
    offset: int
    length: int


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_dbf(path: Path) -> Iterator[tuple[int, dict[str, str]]]:
    """Yield non-deleted dBASE records as stripped strings."""

    with path.open("rb") as handle:
        header = handle.read(32)
        if len(header) != 32:
            raise ValueError(f"Truncated DBF header: {path}")
        record_count = struct.unpack_from("<I", header, 4)[0]
        header_length = struct.unpack_from("<H", header, 8)[0]
        record_length = struct.unpack_from("<H", header, 10)[0]
        descriptor_bytes = handle.read(header_length - 32)
        fields: list[DbfField] = []
        offset = 1
        for cursor in range(0, len(descriptor_bytes) - 1, 32):
            descriptor = descriptor_bytes[cursor : cursor + 32]
            if not descriptor or descriptor[0] == 0x0D:
                break
            name = descriptor[:11].split(b"\x00", 1)[0].decode("ascii")
            length = descriptor[16]
            fields.append(DbfField(name=name, offset=offset, length=length))
            offset += length
        if offset != record_length:
            raise ValueError(
                f"DBF record layout mismatch for {path}: fields={offset}, header={record_length}"
            )

        for index in range(record_count):
            record = handle.read(record_length)
            if len(record) != record_length:
                raise ValueError(f"Truncated DBF record {index}: {path}")
            if record[:1] == b"*":
                continue
            values = {
                field.name: record[field.offset : field.offset + field.length]
                .decode("utf-8", errors="strict")
                .strip()
                for field in fields
            }
            yield index, values


def find_dbf_records(path: Path, field: str, value: str) -> list[tuple[int, dict[str, str]]]:
    matches = [(index, row) for index, row in read_dbf(path) if row.get(field) == value]
    return matches


def optional_int(value: str) -> int | None:
    stripped = value.strip()
    return int(stripped) if stripped else None


def read_shx_entry(path: Path, record_index: int) -> tuple[int, int]:
    with path.open("rb") as handle:
        handle.seek(100 + record_index * 8)
        entry = handle.read(8)
    if len(entry) != 8:
        raise ValueError(f"Missing SHX record {record_index}: {path}")
    offset_words, length_words = struct.unpack(">II", entry)
    return offset_words * 2, length_words * 2


def read_multipatch(shp_path: Path, shx_path: Path, record_index: int) -> dict[str, Any]:
    offset, expected_length = read_shx_entry(shx_path, record_index)
    with shp_path.open("rb") as handle:
        handle.seek(offset)
        record_header = handle.read(8)
        if len(record_header) != 8:
            raise ValueError(f"Missing SHP record {record_index}: {shp_path}")
        _, content_words = struct.unpack(">II", record_header)
        content = handle.read(content_words * 2)
    if len(content) != expected_length:
        raise ValueError(
            f"SHP/SHX size mismatch for record {record_index}: {len(content)} != {expected_length}"
        )
    if len(content) < 44:
        raise ValueError(f"Truncated MultiPatch record {record_index}: {shp_path}")
    shape_type = struct.unpack_from("<I", content, 0)[0]
    if shape_type != MULTIPATCH:
        raise ValueError(f"Record {record_index} is shape type {shape_type}, expected MultiPatch")
    bbox = list(struct.unpack_from("<4d", content, 4))
    part_count, point_count = struct.unpack_from("<2I", content, 36)
    cursor = 44
    parts = list(struct.unpack_from(f"<{part_count}I", content, cursor))
    cursor += part_count * 4
    part_types = list(struct.unpack_from(f"<{part_count}I", content, cursor))
    cursor += part_count * 4
    xy = list(struct.iter_unpack("<2d", content[cursor : cursor + point_count * 16]))
    cursor += point_count * 16
    z_min, z_max = struct.unpack_from("<2d", content, cursor)
    cursor += 16
    z_values = struct.unpack_from(f"<{point_count}d", content, cursor)
    points = [[xy[index][0], xy[index][1], z_values[index]] for index in range(point_count)]
    return {
        "bbox_xy": bbox,
        "z_min": z_min,
        "z_max": z_max,
        "parts": parts,
        "part_types": part_types,
        "points": points,
    }


def _same_point(a: Sequence[float], b: Sequence[float], epsilon: float = 1.0e-7) -> bool:
    return all(abs(float(a[index]) - float(b[index])) <= epsilon for index in range(3))


def _normal(points: Sequence[Sequence[float]]) -> tuple[float, float, float]:
    nx = ny = nz = 0.0
    for index, current in enumerate(points):
        following = points[(index + 1) % len(points)]
        nx += (current[1] - following[1]) * (current[2] + following[2])
        ny += (current[2] - following[2]) * (current[0] + following[0])
        nz += (current[0] - following[0]) * (current[1] + following[1])
    return nx, ny, nz


def _project(points: Sequence[Sequence[float]]) -> list[tuple[float, float]]:
    normal = _normal(points)
    drop_axis = max(range(3), key=lambda index: abs(normal[index]))
    keep = [index for index in range(3) if index != drop_axis]
    return [(float(point[keep[0]]), float(point[keep[1]])) for point in points]


def _area2(points: Sequence[tuple[float, float]]) -> float:
    return sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )


def _inside_triangle(
    point: tuple[float, float],
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    epsilon: float = 1.0e-10,
) -> bool:
    def cross(p: tuple[float, float], q: tuple[float, float], r: tuple[float, float]) -> float:
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    values = (cross(a, b, point), cross(b, c, point), cross(c, a, point))
    return min(values) >= -epsilon or max(values) <= epsilon


def triangulate_ring(raw_points: Sequence[Sequence[float]]) -> list[tuple[int, int, int]]:
    points = list(raw_points)
    if len(points) >= 2 and _same_point(points[0], points[-1]):
        points.pop()
    if len(points) < 3:
        return []
    projected = _project(points)
    orientation = 1.0 if _area2(projected) > 0.0 else -1.0
    remaining = list(range(len(points)))
    triangles: list[tuple[int, int, int]] = []
    guard = len(points) * len(points)
    while len(remaining) > 3 and guard > 0:
        guard -= 1
        clipped = False
        for position, current in enumerate(remaining):
            previous = remaining[position - 1]
            following = remaining[(position + 1) % len(remaining)]
            a, b, c = projected[previous], projected[current], projected[following]
            cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if cross * orientation <= 1.0e-10:
                continue
            if any(
                _inside_triangle(projected[other], a, b, c)
                for other in remaining
                if other not in (previous, current, following)
            ):
                continue
            triangles.append((previous, current, following))
            del remaining[position]
            clipped = True
            break
        if not clipped:
            raise ValueError("Could not triangulate an UrbIS face ring deterministically")
    if len(remaining) == 3:
        triangles.append(tuple(remaining))
    return triangles


def multipatch_triangles(patch: dict[str, Any]) -> list[list[list[float]]]:
    parts: list[int] = patch["parts"]
    part_types: list[int] = patch["part_types"]
    points: list[list[float]] = patch["points"]
    triangles: list[list[list[float]]] = []
    for part_index, start in enumerate(parts):
        finish = parts[part_index + 1] if part_index + 1 < len(parts) else len(points)
        ring = points[start:finish]
        part_type = part_types[part_index]
        indices: list[tuple[int, int, int]] = []
        if part_type == PART_TRIANGLE_STRIP:
            indices = [
                (index, index + 1, index + 2) if index % 2 == 0 else (index + 1, index, index + 2)
                for index in range(len(ring) - 2)
            ]
        elif part_type == PART_TRIANGLE_FAN:
            indices = [(0, index, index + 1) for index in range(1, len(ring) - 1)]
        elif part_type in (PART_OUTER_RING, PART_FIRST_RING, PART_RING):
            clean_ring = ring[:-1] if len(ring) >= 2 and _same_point(ring[0], ring[-1]) else ring
            indices = triangulate_ring(clean_ring)
            ring = clean_ring
        elif part_type == PART_INNER_RING:
            raise ValueError("Inner rings require hole-aware triangulation and are not silently discarded")
        else:
            raise ValueError(f"Unsupported MultiPatch part type: {part_type}")
        triangles.extend([[ring[a], ring[b], ring[c]] for a, b, c in indices])
    return triangles


def transform_point(
    point: Sequence[float], origin_e: float, origin_n: float, world_x: float, world_z: float, base_z: float
) -> list[float]:
    return [
        round(world_x + float(point[0]) - origin_e, 4),
        round(float(point[2]) - base_z, 4),
        round(world_z - (float(point[1]) - origin_n), 4),
    ]


def extract(args: argparse.Namespace) -> dict[str, Any]:
    root: Path = args.source_root
    prefix = root / args.prefix
    faces_shp = prefix.with_name(prefix.name + "_BuildingFaces.shp")
    faces_shx = prefix.with_name(prefix.name + "_BuildingFaces.shx")
    solids_shp = prefix.with_name(prefix.name + "_BuildingSolids.shp")
    solid_matches = find_dbf_records(prefix.with_name(prefix.name + "_BuildingSolids.dbf"), "BU_ID", args.building_id)
    if len(solid_matches) != 1:
        raise ValueError(f"Expected exactly one solid for {args.building_id}, got {len(solid_matches)}")
    solid_index, solid_row = solid_matches[0]
    solid_id = solid_row["INSPIRE_ID"]
    # The product specification explicitly notes that solid classes are not
    # supported in every distribution format.  In the official SHP tile the
    # stable solid row can therefore have a NULL geometry; BuildingFaces are
    # the authoritative LoD2 geometry and reference that stable row ID.

    face_matches = find_dbf_records(prefix.with_name(prefix.name + "_BuildingFaces.dbf"), "BUSOLID_ID", solid_id)
    if not face_matches:
        raise ValueError(f"No BuildingFaces refer to solid {solid_id}")
    raw_faces: list[dict[str, Any]] = []
    all_x: list[float] = []
    all_y: list[float] = []
    all_z: list[float] = []
    part_type_counts: dict[str, int] = {}
    for face_index, face_row in face_matches:
        patch = read_multipatch(
            faces_shp,
            faces_shx,
            face_index,
        )
        triangles = multipatch_triangles(patch)
        all_x.extend(point[0] for triangle in triangles for point in triangle)
        all_y.extend(point[1] for triangle in triangles for point in triangle)
        all_z.extend(point[2] for triangle in triangles for point in triangle)
        for part_type in patch["part_types"]:
            key = str(part_type)
            part_type_counts[key] = part_type_counts.get(key, 0) + 1
        raw_faces.append(
            {
                "id": face_row["INSPIRE_ID"],
                "type": face_row["TYPE"],
                "details_level": optional_int(face_row["DETAILSLEV"]),
                "triangles": triangles,
            }
        )
    if not all_z or not all(math.isfinite(value) for value in all_z):
        raise ValueError("UrbIS hero contains no finite Z coordinates")

    ground_z_values = [
        point[2]
        for face in raw_faces
        if face["type"] == "GROUNDSURFACE"
        for triangle in face["triangles"]
        for point in triangle
    ]
    base_z = min(ground_z_values) if ground_z_values else min(all_z)
    faces = [
        {
            **{key: face[key] for key in ("id", "type", "details_level")},
            "triangles": [
                [
                    transform_point(
                        point,
                        args.origin_e,
                        args.origin_n,
                        args.world_x,
                        args.world_z,
                        base_z,
                    )
                    for point in triangle
                ]
                for triangle in face["triangles"]
            ],
        }
        for face in raw_faces
    ]
    type_counts: dict[str, int] = {}
    triangle_count = 0
    for face in faces:
        type_counts[face["type"]] = type_counts.get(face["type"], 0) + 1
        triangle_count += len(face["triangles"])

    return {
        "schema": "grand-bruxelles-urbis-hero-mesh-v1",
        "hero_id": args.hero_id,
        "name": args.name,
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS - 3D Constructions",
            "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
            "dataset_url": "https://datastore.brussels/web/data/dataset/e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
            "package_url": args.package_url,
            "package_sha256": args.package_sha256.lower(),
            "building_faces_shp_sha256": sha256_file(faces_shp),
            "building_solids_shp_sha256": sha256_file(solids_shp),
            "package_revision": args.package_revision,
            "license": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/legalcode",
            "crs": "EPSG:31370",
            "accessed_at": args.accessed_at,
            "building_2d_id": args.building_id,
            "building_solid_id": solid_id,
            "details_level": optional_int(solid_row["DETAILSLEV"]),
        },
        "transform": {
            "lambert72_origin": [args.origin_e, args.origin_n],
            "world_origin": [args.world_x, 0.0, args.world_z],
            "source_base_z": round(base_z, 4),
        },
        "evidence": {
            "source_bbox_xy": [
                round(min(all_x), 4),
                round(min(all_y), 4),
                round(max(all_x), 4),
                round(max(all_y), 4),
            ],
            "source_z_min": round(min(all_z), 4),
            "source_z_max": round(max(all_z), 4),
            "height_m": round(max(all_z) - base_z, 4),
            "face_count": len(faces),
            "face_type_counts": type_counts,
            "triangle_count": triangle_count,
            "multipatch_part_type_counts": part_type_counts,
        },
        "runtime_approved": False,
        "approval_note": "Authoritative CC0 LoD2 geometry; visual/photo-match and performance approval remain required.",
        "faces": faces,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--prefix", default="UrbISBuildings3D_148170")
    parser.add_argument("--building-id", required=True)
    parser.add_argument("--hero-id", required=True)
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
    print(
        "URBIS_HERO_EXTRACT:",
        result["hero_id"],
        "faces=", result["evidence"]["face_count"],
        "triangles=", result["evidence"]["triangle_count"],
        "height_m=", result["evidence"]["height_m"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
