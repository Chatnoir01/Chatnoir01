#!/usr/bin/env python3
"""Materialize one locked C01 UrbIS LoD2 distribution directly into physical 500 m cell artifacts.

The source URL and every source hash come from the already locked exact C01 summary.
No Atom feed traversal is performed here. Output preserves original EPSG:31370 XYZ,
official IDs and raw face types. No game-world transform, collision or runtime mount
is authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import re
import tempfile
import urllib.parse
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import shapefile

ALLOWED_HOST = "urbisdownload.datastore.brussels"
TILE_RE = re.compile(r"shp_(\d{6})_\{date\}\.zip$", re.I)


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def owner_sequence_sha256(values: list[str]) -> str:
    return sha256_bytes(("\n".join(values) + "\n").encode("utf-8"))


def validate_common(selection: dict[str, Any], summary: dict[str, Any], contract: dict[str, Any]) -> None:
    expected = contract["expected"]
    if selection.get("campaign_id") != contract["campaign_id"]:
        raise RuntimeError("selection campaign mismatch")
    if summary.get("campaign_id") != contract["campaign_id"]:
        raise RuntimeError("summary campaign mismatch")
    if summary.get("status") != "locked-exact":
        raise RuntimeError("source summary must remain locked-exact")
    if int(selection.get("owner_count", -1)) != int(expected["owner_count"]):
        raise RuntimeError("selection owner count drift")
    if selection.get("owner_sequence_sha256") != expected["owner_sequence_sha256"]:
        raise RuntimeError("selection owner sequence drift")
    metrics = summary.get("metrics", {})
    for key in ["owner_count", "solid_count", "face_count", "point_count", "part_count", "canonical_payload_bytes", "source_shard_count"]:
        if int(metrics.get(key, -1)) != int(expected[key]):
            raise RuntimeError(f"summary metric drift: {key}")
    if metrics.get("source_shards_sha256") != expected["source_shards_sha256"]:
        raise RuntimeError("summary source-shards digest drift")
    if metrics.get("face_type_counts") != expected["face_type_counts"]:
        raise RuntimeError("summary face-type counts drift")
    for source in [selection, summary]:
        for key in [
            "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
            "geometry_modified", "game_world_transform_authorized", "jouable_promotion_authorized",
        ]:
            if source.get(key) is not False:
                raise RuntimeError(f"locked input must keep {key}=false")
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "game_world_transform_authorized", "jouable_promotion_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")
    if hard.get("artifact_source_materialization_only") is not True:
        raise RuntimeError("artifact_source_materialization_only must remain true")
    if hard.get("source_geometry_modified") is not False:
        raise RuntimeError("source_geometry_modified must remain false")


def groups_for_distribution(selection: dict[str, Any], distribution_key: str) -> list[dict[str, Any]]:
    groups = [
        group for group in selection.get("groups", [])
        if str(group.get("distribution_key", "")).lower() == distribution_key.lower()
    ]
    if not groups:
        raise RuntimeError(f"distribution absent from selection: {distribution_key}")
    return groups


def selected_owner_context(groups: list[dict[str, Any]]) -> tuple[list[str], dict[str, str]]:
    selected: list[str] = []
    owner_to_cell: dict[str, str] = {}
    for group in groups:
        cell_id = str(group["cell_id"])
        for raw in group["owner_ids"]:
            building_id = str(raw)
            if not building_id.isdigit():
                raise RuntimeError(f"invalid BU_ID {building_id!r}")
            if building_id in owner_to_cell:
                raise RuntimeError(f"BU_ID duplicated in distribution groups: {building_id}")
            owner_to_cell[building_id] = cell_id
            selected.append(building_id)
    return selected, owner_to_cell


def validate_locked_shard(groups: list[dict[str, Any]], selected: list[str], locked: dict[str, Any]) -> None:
    shard_selection = locked["selection"]
    if len(selected) != int(shard_selection["owner_count"]):
        raise RuntimeError("distribution owner count drift")
    if owner_sequence_sha256(selected) != shard_selection["owner_ids_sha256"]:
        raise RuntimeError("distribution owner sequence drift")
    cells = sorted({str(group["cell_id"]) for group in groups})
    municipalities = sorted({str(group["municipality"]) for group in groups})
    if cells != list(shard_selection["cells"]):
        raise RuntimeError("distribution cell membership drift")
    if municipalities != list(shard_selection["municipalities"]):
        raise RuntimeError("distribution municipality membership drift")
    if len(groups) != int(shard_selection["planner_groups"]):
        raise RuntimeError("distribution planner-group count drift")


def validate_direct_source(locked: dict[str, Any], distribution_key: str) -> tuple[str, str]:
    source = locked["source"]
    url = str(source["distribution_url"])
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != ALLOWED_HOST:
        raise RuntimeError(f"locked distribution URL must use {ALLOWED_HOST}")
    if str(source["revision"]) != "20260808":
        raise RuntimeError("locked source revision drift")
    match = TILE_RE.search(distribution_key)
    if match is None:
        raise RuntimeError(f"unexpected distribution key {distribution_key}")
    return url, match.group(1)


def run(repo_root: Path, selection_path: Path, summary_path: Path, contract_path: Path, distribution_key: str, output_root: Path) -> dict[str, Any]:
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    validate_common(selection, summary, contract)

    locked = summary.get("source_shards", {}).get(distribution_key)
    if not isinstance(locked, dict):
        raise RuntimeError(f"distribution missing from locked source summary: {distribution_key}")
    groups = groups_for_distribution(selection, distribution_key)
    selected, owner_to_cell = selected_owner_context(groups)
    validate_locked_shard(groups, selected, locked)
    direct_url, tile = validate_direct_source(locked, distribution_key)

    verifier = load_module(
        "urbis_batch_verifier",
        repo_root / "grand-bruxelles-game/tools/qa/verify_urbis_lod2_source_batch.py",
    )
    audit = load_module(
        "urbis_batch_complexity",
        repo_root / "grand-bruxelles-game/tools/qa/audit_urbis_lod2_batch_complexity.py",
    )

    package = verifier.http_get(direct_url, timeout=180, retries=4)
    source = locked["source"]
    if sha256_bytes(package) != source["package_sha256"]:
        raise RuntimeError("official package SHA-256 drift")
    owners, solids_stats = verifier.read_owner_evidence(package)
    if solids_stats["building_solids_shp_sha256"] != source["building_solids_shp_sha256"]:
        raise RuntimeError("BuildingSolids SHP SHA-256 drift")
    if solids_stats["building_solids_dbf_sha256"] != source["building_solids_dbf_sha256"]:
        raise RuntimeError("BuildingSolids DBF SHA-256 drift")

    solid_to_owner: dict[str, str] = {}
    for building_id in selected:
        owner = owners.get(building_id)
        if owner is None:
            raise RuntimeError(f"locked BU_ID missing from official package: {building_id}")
        solid_ids = [str(value) for value in owner["solid_ids"]]
        if not solid_ids:
            raise RuntimeError(f"locked BU_ID has no official solid: {building_id}")
        for solid_id in solid_ids:
            previous = solid_to_owner.setdefault(solid_id, building_id)
            if previous != building_id:
                raise RuntimeError(f"solid maps to multiple selected owners: {solid_id}")

    selected_urls = set(solid_to_owner)
    selected_numeric = {value.rsplit("/", 1)[-1] for value in selected_urls}
    matched_solids: set[str] = set()
    face_types: Counter[str] = Counter()
    cell_stats: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"owners": set(), "solids": set(), "faces": 0, "points": 0, "parts": 0, "bytes": 0}
    )
    total_faces = total_points = total_parts = total_bytes = 0
    canonical_hasher = hashlib.sha256()

    shard_root = output_root / tile
    cell_root = shard_root / "cells"
    cell_root.mkdir(parents=True, exist_ok=True)
    handles: dict[str, Any] = {}

    try:
        with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
            shp_name = audit.layer_member(archive, "buildingface", ".shp")
            dbf_name = audit.layer_member(archive, "buildingface", ".dbf")
            shx_name = audit.layer_member(archive, "buildingface", ".shx")
            if not shp_name or not dbf_name:
                raise RuntimeError("BuildingFaces SHP/DBF missing")
            if sha256_bytes(archive.read(shp_name)) != source["building_faces_shp_sha256"]:
                raise RuntimeError("BuildingFaces SHP SHA-256 drift")
            if sha256_bytes(archive.read(dbf_name)) != source["building_faces_dbf_sha256"]:
                raise RuntimeError("BuildingFaces DBF SHA-256 drift")

            for name in [shp_name, dbf_name] + ([shx_name] if shx_name else []):
                archive.extract(name, tmp)
            kwargs: dict[str, str] = {
                "shp": str(Path(tmp) / shp_name),
                "dbf": str(Path(tmp) / dbf_name),
            }
            if shx_name:
                kwargs["shx"] = str(Path(tmp) / shx_name)
            reader = shapefile.Reader(**kwargs, encoding="utf-8", encodingErrors="replace")

            for shape_record in reader.iterShapeRecords():
                values = shape_record.record.as_dict()
                solid_id = audit.record_solid(values, selected_urls, selected_numeric)
                if not solid_id:
                    continue
                building_id = solid_to_owner[solid_id]
                cell_id = owner_to_cell[building_id]
                face_id = audit.record_face_id(values)
                if not face_id:
                    raise RuntimeError(f"selected solid {solid_id} has face without official face ID")
                raw_type = str(values.get("TYPE") or "").strip()
                if not raw_type:
                    raise RuntimeError(f"selected face {face_id} has empty raw TYPE")
                parts, points_here, parts_here = audit.part_payload(shape_record.shape)
                if not parts:
                    raise RuntimeError(f"selected face {face_id} has no source MultiPatch parts")
                line = (
                    json.dumps(
                        {
                            "building_id": building_id,
                            "solid_id": solid_id,
                            "face_id": face_id,
                            "face_type": raw_type,
                            "parts": parts,
                        },
                        ensure_ascii=False,
                        separators=(",", ":"),
                    )
                    + "\n"
                ).encode("utf-8")

                if cell_id not in handles:
                    path = cell_root / f"{cell_id}.source.ndjson"
                    handles[cell_id] = path.open("wb")
                handles[cell_id].write(line)

                canonical_hasher.update(line)
                total_bytes += len(line)
                total_faces += 1
                total_points += points_here
                total_parts += parts_here
                face_types[raw_type] += 1
                matched_solids.add(solid_id)
                stat = cell_stats[cell_id]
                stat["owners"].add(building_id)
                stat["solids"].add(solid_id)
                stat["faces"] += 1
                stat["points"] += points_here
                stat["parts"] += parts_here
                stat["bytes"] += len(line)
    finally:
        for handle in handles.values():
            handle.close()

    missing_solids = selected_urls - matched_solids
    if missing_solids:
        raise RuntimeError(f"{len(missing_solids)} selected solids have no BuildingFaces")

    expected_selection = locked["selection"]
    observed = {
        "owner_count": len(selected),
        "solid_count": len(selected_urls),
        "face_count": total_faces,
        "point_count": total_points,
        "part_count": total_parts,
        "face_type_counts": dict(sorted(face_types.items())),
    }
    for key, value in observed.items():
        if value != expected_selection[key]:
            raise RuntimeError(f"locked distribution metric drift: {key}")
    expected_payload = locked["canonical_payload"]
    if total_bytes != int(expected_payload["bytes"]):
        raise RuntimeError("canonical payload byte count drift")
    if canonical_hasher.hexdigest() != expected_payload["sha256"]:
        raise RuntimeError("canonical payload digest drift")

    expected_cell_owners: dict[str, set[str]] = defaultdict(set)
    for building_id, cell_id in owner_to_cell.items():
        expected_cell_owners[cell_id].add(building_id)
    if set(cell_stats) != set(expected_cell_owners):
        raise RuntimeError("materialized cell set drift")

    cells_report: dict[str, Any] = {}
    for cell_id in sorted(cell_stats):
        stat = cell_stats[cell_id]
        if stat["owners"] != expected_cell_owners[cell_id]:
            raise RuntimeError(f"materialized owner coverage drift in {cell_id}")
        path = cell_root / f"{cell_id}.source.ndjson"
        cells_report[cell_id] = {
            "owner_count": len(stat["owners"]),
            "solid_count": len(stat["solids"]),
            "face_count": stat["faces"],
            "point_count": stat["points"],
            "part_count": stat["parts"],
            "bytes": stat["bytes"],
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "relative_path": f"{tile}/cells/{cell_id}.source.ndjson",
        }

    report = {
        "schema": "grand-bruxelles-region-lod2-source-materialized-shard-v1",
        "campaign_id": contract["campaign_id"],
        "distribution_key": distribution_key,
        "tile": tile,
        "source": source,
        "selection": {
            **observed,
            "owner_ids_sha256": owner_sequence_sha256(selected),
            "cells": sorted(expected_cell_owners),
            "planner_groups": len(groups),
        },
        "canonical_payload": {
            "bytes": total_bytes,
            "sha256": canonical_hasher.hexdigest(),
        },
        "cells": cells_report,
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
    (shard_root / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "REGION_LOD2_C01_SOURCE_SHARD_MATERIALIZED: "
        f"tile={tile} owners={len(selected)} solids={len(selected_urls)} "
        f"faces={total_faces} points={total_points} parts={total_parts} bytes={total_bytes}",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--distribution-key", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(
            args.repo_root.resolve(),
            args.selection.resolve(),
            args.summary.resolve(),
            args.contract.resolve(),
            args.distribution_key,
            args.output_root.resolve(),
        )
    except Exception as exc:
        print(f"REGION_LOD2_C01_SOURCE_SHARD_MATERIALIZATION_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
