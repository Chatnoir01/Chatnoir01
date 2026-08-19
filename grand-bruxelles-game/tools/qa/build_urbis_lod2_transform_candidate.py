#!/usr/bin/env python3
"""Build an artifact-only game-coordinate candidate from an UrbIS LoD2 source batch.

Horizontal X/Z uses the established global Lambert72 -> current game-world anchor.
Vertical source Z is never discarded. A per-owner local_y is derived only to
preserve LoD2 shape; it is explicitly not a final terrain-mounted world Y.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def load_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            text = line.strip()
            if not text:
                continue
            try:
                row = json.loads(text)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"invalid NDJSON line {line_number}: {exc}") from exc
            records.append(row)
    return records


def iter_vertices(record: dict[str, Any]):
    for part in record.get("parts", []):
        for vertex in part.get("vertices", []):
            if not isinstance(vertex, list) or len(vertex) < 3:
                raise RuntimeError(f"invalid source vertex in face {record.get('face_id')}")
            if vertex[2] is None:
                raise RuntimeError(f"source Z missing in face {record.get('face_id')}")
            yield float(vertex[0]), float(vertex[1]), float(vertex[2])


def validate_source(
    records: list[dict[str, Any]],
    contract: dict[str, Any],
    source_payload: bytes,
) -> tuple[dict[str, float], dict[str, float], dict[str, Any]]:
    expected = contract["expected_source"]
    if sha256_bytes(source_payload) != expected["source_payload_sha256"]:
        raise RuntimeError("source payload SHA-256 drift")

    owners: set[str] = set()
    solids: set[str] = set()
    faces: set[str] = set()
    face_types: Counter[str] = Counter()
    owner_min_z: dict[str, float] = {}
    owner_max_z: dict[str, float] = {}
    point_count = 0
    part_count = 0
    source_e: list[float] = []
    source_n: list[float] = []
    source_z: list[float] = []

    for row in records:
        building_id = str(row.get("building_id") or "")
        solid_id = str(row.get("solid_id") or "")
        face_id = str(row.get("face_id") or "")
        face_type = str(row.get("face_type") or "")
        if not all([building_id, solid_id, face_id, face_type]):
            raise RuntimeError("source face record is missing an official identifier/type")
        if face_id in faces:
            raise RuntimeError(f"duplicate official face ID {face_id}")
        owners.add(building_id)
        solids.add(solid_id)
        faces.add(face_id)
        face_types[face_type] += 1
        part_count += len(row.get("parts", []))

        seen_vertex = False
        for easting, northing, elevation in iter_vertices(row):
            seen_vertex = True
            point_count += 1
            source_e.append(easting)
            source_n.append(northing)
            source_z.append(elevation)
            owner_min_z[building_id] = min(owner_min_z.get(building_id, elevation), elevation)
            owner_max_z[building_id] = max(owner_max_z.get(building_id, elevation), elevation)
        if not seen_vertex:
            raise RuntimeError(f"face {face_id} has no source vertices")

    actual = {
        "owners": len(owners),
        "solids": len(solids),
        "faces": len(faces),
        "points": point_count,
        "parts": part_count,
    }
    for key, value in actual.items():
        if int(expected[key]) != value:
            raise RuntimeError(f"source {key} drift: expected {expected[key]}, got {value}")

    if set(owner_min_z) != owners or set(owner_max_z) != owners:
        raise RuntimeError("owner vertical coverage is incomplete")

    summary = {
        "face_type_counts": dict(sorted(face_types.items())),
        "source_extent": {
            "min_e": min(source_e),
            "max_e": max(source_e),
            "min_n": min(source_n),
            "max_n": max(source_n),
            "min_z": min(source_z),
            "max_z": max(source_z),
        },
    }
    return owner_min_z, owner_max_z, summary


def build_candidate(
    records: list[dict[str, Any]],
    owner_min_z: dict[str, float],
    contract: dict[str, Any],
    output_path: Path,
) -> dict[str, Any]:
    horizontal = contract["horizontal_transform"]
    vertical = contract["vertical_candidate"]
    decimals = int(horizontal["runtime_quantization_decimals"])
    vertical_decimals = int(vertical["runtime_quantization_decimals"])
    origin_e = float(horizontal["lambert_origin_e"])
    origin_n = float(horizontal["lambert_origin_n"])
    anchor_x = float(horizontal["world_anchor_x"])
    anchor_z = float(horizontal["world_anchor_z"])

    max_plan_quantization_error = 0.0
    max_local_y_quantization_error = 0.0
    world_x_values: list[float] = []
    world_z_values: list[float] = []
    local_y_values: list[float] = []

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in records:
            building_id = str(row["building_id"])
            base_z = owner_min_z[building_id]
            candidate_parts: list[dict[str, Any]] = []

            for part in row.get("parts", []):
                candidate_vertices: list[dict[str, list[float]]] = []
                for raw in part.get("vertices", []):
                    easting = float(raw[0])
                    northing = float(raw[1])
                    source_z = float(raw[2])
                    world_x_exact = easting - origin_e + anchor_x
                    world_z_exact = -(northing - origin_n) + anchor_z
                    local_y_exact = source_z - base_z
                    if local_y_exact < -1e-8:
                        raise RuntimeError(f"negative local_y for owner {building_id}")

                    world_x = round(world_x_exact, decimals)
                    world_z = round(world_z_exact, decimals)
                    local_y = round(local_y_exact, vertical_decimals)
                    max_plan_quantization_error = max(
                        max_plan_quantization_error,
                        abs(world_x - world_x_exact),
                        abs(world_z - world_z_exact),
                    )
                    max_local_y_quantization_error = max(
                        max_local_y_quantization_error,
                        abs(local_y - local_y_exact),
                    )
                    world_x_values.append(world_x)
                    world_z_values.append(world_z)
                    local_y_values.append(local_y)
                    candidate_vertices.append({
                        "source_xyz": [easting, northing, source_z],
                        "candidate_x_localy_z": [world_x, local_y, world_z],
                    })
                candidate_parts.append({
                    "part_type": part.get("part_type"),
                    "vertices": candidate_vertices,
                })

            output = {
                "building_id": building_id,
                "solid_id": row["solid_id"],
                "face_id": row["face_id"],
                "face_type": row["face_type"],
                "owner_base_source_z": base_z,
                "vertical_status": "owner_local_shape_only_not_world_y",
                "parts": candidate_parts,
            }
            handle.write(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")

    quantization_limit = 0.5 * (10 ** (-decimals)) + 1e-12
    vertical_quantization_limit = 0.5 * (10 ** (-vertical_decimals)) + 1e-12
    if max_plan_quantization_error > quantization_limit:
        raise RuntimeError("horizontal quantization exceeded configured 3-decimal bound")
    if max_local_y_quantization_error > vertical_quantization_limit:
        raise RuntimeError("local_y quantization exceeded configured 3-decimal bound")

    return {
        "candidate_extent": {
            "min_world_x": min(world_x_values),
            "max_world_x": max(world_x_values),
            "min_world_z": min(world_z_values),
            "max_world_z": max(world_z_values),
            "min_local_y": min(local_y_values),
            "max_local_y": max(local_y_values),
        },
        "max_plan_quantization_error_m": max_plan_quantization_error,
        "max_local_y_quantization_error_m": max_local_y_quantization_error,
    }


def run(source_path: Path, contract_path: Path, output_path: Path, report_path: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "final_world_y_authorized",
        "source_geometry_modified",
        "semantic_names_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"transform contract must keep {key}=false")
    if hard.get("artifact_only") is not True:
        raise RuntimeError("transform candidate must remain artifact_only=true")
    if contract["vertical_candidate"].get("final_world_y_authorized") is not False:
        raise RuntimeError("vertical candidate must not authorize final world Y")

    source_payload = source_path.read_bytes()
    records = load_records(source_path)
    owner_min_z, owner_max_z, source_summary = validate_source(records, contract, source_payload)
    candidate_summary = build_candidate(records, owner_min_z, contract, output_path)

    heights = [owner_max_z[key] - owner_min_z[key] for key in sorted(owner_min_z, key=int)]
    output_payload = output_path.read_bytes()
    report = {
        "schema": "grand-bruxelles-urbis-lod2-transform-candidate-report-v1",
        "batch_id": contract["batch_id"],
        "source_sha256": sha256_bytes(source_payload),
        "source_bytes": len(source_payload),
        "source": source_summary,
        "owner_vertical_evidence": {
            "owner_count": len(owner_min_z),
            "min_owner_base_source_z": min(owner_min_z.values()),
            "max_owner_base_source_z": max(owner_min_z.values()),
            "min_owner_height_m": min(heights),
            "median_owner_height_m": statistics.median(heights),
            "max_owner_height_m": max(heights),
        },
        "candidate": {
            **candidate_summary,
            "output_bytes": len(output_payload),
            "output_sha256": sha256_bytes(output_payload),
            "horizontal_transform": contract["horizontal_transform"],
            "vertical_candidate": contract["vertical_candidate"],
        },
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "final_world_y_authorized": False,
        "artifact_only": True,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "URBIS_LOD2_TRANSFORM_CANDIDATE_OK: "
        f"owners={len(owner_min_z)} faces={len(records)} "
        f"world_x={candidate_summary['candidate_extent']['min_world_x']}..{candidate_summary['candidate_extent']['max_world_x']} "
        f"world_z={candidate_summary['candidate_extent']['min_world_z']}..{candidate_summary['candidate_extent']['max_world_z']} "
        f"max_plan_qerr={candidate_summary['max_plan_quantization_error_m']:.9f} "
        f"final_world_y_authorized=false",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.source.resolve(), args.contract.resolve(), args.output.resolve(), args.report.resolve())
    except Exception as exc:
        print(f"URBIS_LOD2_TRANSFORM_CANDIDATE_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
