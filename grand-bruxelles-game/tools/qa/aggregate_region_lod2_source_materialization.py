#!/usr/bin/env python3
"""Aggregate verified C01 distribution artifacts into 132 physical-cell source payloads."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def owner_sequence_sha256(values: list[str]) -> str:
    return hashlib.sha256(("\n".join(values) + "\n").encode("utf-8")).hexdigest()


def load_expected_cells(selection: dict[str, Any]) -> dict[str, list[str]]:
    cells: dict[str, list[str]] = defaultdict(list)
    seen: set[str] = set()
    for group in selection["groups"]:
        cell_id = str(group["cell_id"])
        for raw in group["owner_ids"]:
            building_id = str(raw)
            if building_id in seen:
                raise RuntimeError(f"owner duplicated in selection: {building_id}")
            seen.add(building_id)
            cells[cell_id].append(building_id)
    return dict(cells)


def aggregate(shards_root: Path, selection_path: Path, summary_path: Path, contract_path: Path, output_root: Path) -> dict[str, Any]:
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    expected = contract["expected"]
    if selection.get("campaign_id") != contract["campaign_id"] or summary.get("campaign_id") != contract["campaign_id"]:
        raise RuntimeError("campaign ID mismatch")
    if summary.get("status") != "locked-exact":
        raise RuntimeError("source summary must remain locked-exact")
    if int(selection.get("owner_count", -1)) != int(expected["owner_count"]):
        raise RuntimeError("selection owner count drift")
    if selection.get("owner_sequence_sha256") != expected["owner_sequence_sha256"]:
        raise RuntimeError("selection owner digest drift")
    if summary.get("metrics", {}).get("source_shards_sha256") != expected["source_shards_sha256"]:
        raise RuntimeError("source summary digest drift")
    for key in ["runtime_authorized", "runtime_mount_authorized", "collision_authorized", "game_world_transform_authorized", "jouable_promotion_authorized", "geometry_modified"]:
        if selection.get(key) is not False or summary.get(key) is not False:
            raise RuntimeError(f"locked evidence must keep {key}=false")

    reports = [json.loads(path.read_text(encoding="utf-8")) for path in sorted(shards_root.glob("*/report.json"))]
    if len(reports) != int(expected["source_shard_count"]):
        raise RuntimeError(f"expected {expected['source_shard_count']} shard reports, got {len(reports)}")
    keys = [str(report["distribution_key"]) for report in reports]
    if len(keys) != len(set(keys)):
        raise RuntimeError("duplicate distribution reports")

    total = Counter()
    face_types = Counter()
    all_cell_chunks: dict[str, list[tuple[str, Path, dict[str, Any]]]] = defaultdict(list)
    for report in reports:
        for key in [
            "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
            "game_world_transform_authorized", "jouable_promotion_authorized", "source_geometry_modified",
        ]:
            if report.get(key) is not False:
                raise RuntimeError(f"shard report must keep {key}=false")
        if report.get("artifact_only") is not True or report.get("artifact_geometry_written") is not True:
            raise RuntimeError("shard must be artifact-only materialized source geometry")
        selection_stats = report["selection"]
        total["owner_count"] += int(selection_stats["owner_count"])
        total["solid_count"] += int(selection_stats["solid_count"])
        total["face_count"] += int(selection_stats["face_count"])
        total["point_count"] += int(selection_stats["point_count"])
        total["part_count"] += int(selection_stats["part_count"])
        total["canonical_payload_bytes"] += int(report["canonical_payload"]["bytes"])
        face_types.update(selection_stats["face_type_counts"])

        for cell_id, cell in report["cells"].items():
            rel = Path(str(cell["relative_path"]))
            path = shards_root / rel
            if not path.is_file():
                raise RuntimeError(f"missing cell shard file: {path}")
            if path.stat().st_size != int(cell["bytes"]):
                raise RuntimeError(f"cell shard byte drift: {path}")
            if sha256_path(path) != cell["sha256"]:
                raise RuntimeError(f"cell shard digest drift: {path}")
            all_cell_chunks[str(cell_id)].append((str(report["distribution_key"]), path, cell))

    for key in ["owner_count", "solid_count", "face_count", "point_count", "part_count", "canonical_payload_bytes"]:
        if int(total[key]) != int(expected[key]):
            raise RuntimeError(f"campaign aggregate drift: {key} {total[key]} != {expected[key]}")
    if dict(sorted(face_types.items())) != expected["face_type_counts"]:
        raise RuntimeError("campaign aggregate face-type drift")

    expected_cells = load_expected_cells(selection)
    if len(expected_cells) != int(expected["spatial_cell_count"]):
        raise RuntimeError("selection physical-cell count drift")
    if set(all_cell_chunks) != set(expected_cells):
        raise RuntimeError("materialized physical-cell set drift")

    cells_root = output_root / "cells"
    cells_root.mkdir(parents=True, exist_ok=True)
    cell_index: dict[str, Any] = {}
    campaign_owner_set: set[str] = set()
    campaign_faces = campaign_points = campaign_parts = campaign_bytes = 0

    for cell_id in sorted(expected_cells):
        chunks = sorted(all_cell_chunks[cell_id], key=lambda value: value[0])
        out_path = cells_root / cell_id / "source.ndjson"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        owners_seen: set[str] = set()
        solids_seen: set[str] = set()
        faces = points = parts = bytes_written = 0
        hasher = hashlib.sha256()

        with out_path.open("wb") as out:
            for _distribution_key, chunk_path, _cell_meta in chunks:
                with chunk_path.open("rb") as handle:
                    for raw_line in handle:
                        if not raw_line.strip():
                            continue
                        row = json.loads(raw_line)
                        building_id = str(row["building_id"])
                        owners_seen.add(building_id)
                        solids_seen.add(str(row["solid_id"]))
                        faces += 1
                        parts_here = row.get("parts", [])
                        parts += len(parts_here)
                        points += sum(len(part.get("vertices", [])) for part in parts_here)
                        out.write(raw_line)
                        hasher.update(raw_line)
                        bytes_written += len(raw_line)

        expected_owner_list = expected_cells[cell_id]
        if owners_seen != set(expected_owner_list):
            missing = sorted(set(expected_owner_list) - owners_seen)
            extra = sorted(owners_seen - set(expected_owner_list))
            raise RuntimeError(f"owner coverage drift in {cell_id}: missing={len(missing)} extra={len(extra)}")
        overlap = campaign_owner_set & owners_seen
        if overlap:
            raise RuntimeError(f"owner present in multiple physical cells: {next(iter(overlap))}")
        campaign_owner_set.update(owners_seen)

        if bytes_written != out_path.stat().st_size:
            raise RuntimeError(f"merged byte accounting drift in {cell_id}")
        if hasher.hexdigest() != sha256_path(out_path):
            raise RuntimeError(f"merged digest accounting drift in {cell_id}")

        campaign_faces += faces
        campaign_points += points
        campaign_parts += parts
        campaign_bytes += bytes_written
        cell_index[cell_id] = {
            "owner_count": len(owners_seen),
            "owner_sequence_sha256": owner_sequence_sha256(expected_owner_list),
            "solid_count": len(solids_seen),
            "face_count": faces,
            "point_count": points,
            "part_count": parts,
            "bytes": bytes_written,
            "sha256": hasher.hexdigest(),
            "distribution_count": len(chunks),
            "distributions": [value[0] for value in chunks],
            "relative_path": f"cells/{cell_id}/source.ndjson",
            "coordinate_space": "original EPSG:31370 XYZ",
        }

    if len(campaign_owner_set) != int(expected["owner_count"]):
        raise RuntimeError("final owner coverage drift")
    if campaign_faces != int(expected["face_count"]):
        raise RuntimeError("final face count drift")
    if campaign_points != int(expected["point_count"]):
        raise RuntimeError("final point count drift")
    if campaign_parts != int(expected["part_count"]):
        raise RuntimeError("final part count drift")
    if campaign_bytes != int(expected["canonical_payload_bytes"]):
        raise RuntimeError("final payload byte count drift")

    index = {
        "schema": "grand-bruxelles-region-lod2-source-materialized-cells-v1",
        "campaign_id": contract["campaign_id"],
        "selection": {
            "owner_count": len(campaign_owner_set),
            "owner_sequence_sha256": selection["owner_sequence_sha256"],
            "spatial_cell_count": len(cell_index),
            "source_shard_count": len(reports),
        },
        "source_metrics": {
            "solid_count": int(expected["solid_count"]),
            "face_count": campaign_faces,
            "point_count": campaign_points,
            "part_count": campaign_parts,
            "canonical_payload_bytes": campaign_bytes,
            "face_type_counts": expected["face_type_counts"],
            "source_shards_sha256": expected["source_shards_sha256"],
        },
        "cells": cell_index,
        "artifact_geometry_written": True,
        "coordinate_space": "original EPSG:31370 XYZ",
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "game_world_transform_authorized": False,
        "jouable_promotion_authorized": False,
        "source_geometry_modified": False,
        "artifact_only": True,
    }
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "source_materialization_index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "REGION_LOD2_C01_SOURCE_CELLS_AGGREGATED: "
        f"owners={len(campaign_owner_set)} cells={len(cell_index)} "
        f"faces={campaign_faces} points={campaign_points} parts={campaign_parts} bytes={campaign_bytes}",
        flush=True,
    )
    return index


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shards-root", type=Path, required=True)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        aggregate(
            args.shards_root.resolve(),
            args.selection.resolve(),
            args.summary.resolve(),
            args.contract.resolve(),
            args.output_root.resolve(),
        )
    except Exception as exc:
        print(f"REGION_LOD2_C01_SOURCE_CELLS_AGGREGATION_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
