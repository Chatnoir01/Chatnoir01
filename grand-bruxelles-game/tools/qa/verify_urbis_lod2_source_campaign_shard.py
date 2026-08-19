#!/usr/bin/env python3
"""Verify one distribution shard of a locked regional UrbIS LoD2 source campaign.

The exact 30k owner list is regenerated from an immutable planner artifact by a
separate builder. This verifier consumes that generated selection plus the small
repository campaign manifest, checks one official source distribution, validates
every owner against its locked 500 m cell and official municipality polygon, and
emits deterministic source metrics plus a canonical geometry digest.

Evidence/source-registry only. No game-world transform, runtime mount, collision,
semantic naming or JOUABLE promotion is authorized.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import re
import tempfile
import zipfile
from collections import Counter
from pathlib import Path
from typing import Any

import shapefile
from shapely.geometry import Point, shape as shapely_shape

CELL_RE = re.compile(r"^E(\d+)_N(\d+)$")


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def owner_sequence_sha256(owner_ids: list[str]) -> str:
    return sha256_bytes(("\n".join(owner_ids) + "\n").encode("utf-8"))


def cell_bbox(cell_id: str) -> list[float]:
    match = CELL_RE.fullmatch(cell_id)
    if not match:
        raise RuntimeError(f"invalid 500 m cell id: {cell_id}")
    east = float(match.group(1))
    north = float(match.group(2))
    return [east, north, east + 500.0, north + 500.0]


def load_inputs(
    repo_root: Path,
    manifest_path: Path,
    selection_path: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    contract_path = repo_root / manifest["contract"]
    contract = json.loads(contract_path.read_text(encoding="utf-8"))

    for key in [
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "geometry_modified",
        "semantic_names_authorized",
        "game_world_transform_authorized",
        "jouable_promotion_authorized",
    ]:
        if manifest.get(key) is not False:
            raise RuntimeError(f"campaign manifest must keep {key}=false")
        if selection.get(key) is not False:
            raise RuntimeError(f"generated selection must keep {key}=false")

    hard = contract.get("hard_rules", {})
    for key in [
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "materialization_authorized",
        "geometry_modified",
        "semantic_names_authorized",
        "game_world_transform_authorized",
        "jouable_promotion_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"campaign contract must keep {key}=false")
    if hard.get("source_registration_only") is not True:
        raise RuntimeError("campaign contract must keep source_registration_only=true")
    if not (selection["campaign_id"] == manifest["campaign_id"] == contract["campaign_id"]):
        raise RuntimeError("campaign id mismatch")
    return manifest, contract, selection


def validate_selection(
    manifest: dict[str, Any],
    contract: dict[str, Any],
    selection: dict[str, Any],
) -> list[str]:
    groups = selection.get("groups", [])
    if not isinstance(groups, list) or not groups:
        raise RuntimeError("generated selection.groups is empty")

    owner_ids: list[str] = []
    municipality_counts: Counter[str] = Counter()
    cells: set[tuple[str, str]] = set()
    distributions: set[str] = set()

    for group in groups:
        ids = [str(value) for value in group.get("owner_ids", [])]
        if not ids:
            raise RuntimeError(f"empty group: {group.get('planner_batch_id')}")
        if any(not value.isdigit() for value in ids):
            raise RuntimeError("owner IDs must be numeric strings")
        if ids != sorted(ids, key=int):
            raise RuntimeError(f"group owner order drift: {group['planner_batch_id']}")
        if len(ids) != len(set(ids)):
            raise RuntimeError(f"group owner duplicates: {group['planner_batch_id']}")
        if str(group["revision"]) != str(contract["source"]["revision"]):
            raise RuntimeError(f"group revision drift: {group['planner_batch_id']}")
        municipality = str(group["municipality"])
        municipality_counts[municipality] += len(ids)
        cells.add((municipality, str(group["cell_id"])))
        distributions.add(str(group["distribution_key"]))
        owner_ids.extend(ids)

    if len(owner_ids) != len(set(owner_ids)):
        raise RuntimeError("owner duplicate across generated groups")
    digest = owner_sequence_sha256(owner_ids)
    expected = contract["expected"]
    manifest_selection = manifest["selection"]

    observed = {
        "owner_count": len(owner_ids),
        "owner_sequence_sha256": digest,
        "municipality_counts": dict(municipality_counts),
        "distribution_count": len(distributions),
        "cell_count": len(cells),
        "planner_group_count": len(groups),
    }
    for key, value in observed.items():
        if value != selection[key]:
            raise RuntimeError(f"generated selection self-drift for {key}: {value!r} != {selection[key]!r}")
        if value != expected[key]:
            raise RuntimeError(f"generated/contract drift for {key}: {value!r} != {expected[key]!r}")
        if value != manifest_selection[key]:
            raise RuntimeError(f"generated/manifest drift for {key}: {value!r} != {manifest_selection[key]!r}")

    if selection["first_sequence_owner"] != manifest_selection["first_sequence_owner"]:
        raise RuntimeError("first sequence owner drift")
    if selection["last_sequence_owner"] != manifest_selection["last_sequence_owner"]:
        raise RuntimeError("last sequence owner drift")
    return owner_ids


def shard_groups(selection: dict[str, Any], distribution_key: str) -> list[dict[str, Any]]:
    groups = [
        group
        for group in selection["groups"]
        if str(group["distribution_key"]).lower() == distribution_key.lower()
    ]
    if not groups:
        raise RuntimeError(f"distribution absent from generated selection: {distribution_key}")
    return groups


def verify_shard(
    repo_root: Path,
    manifest_path: Path,
    selection_path: Path,
    distribution_key: str,
    report_path: Path,
) -> dict[str, Any]:
    verifier = load_module(
        "urbis_batch_verifier",
        repo_root / "grand-bruxelles-game/tools/qa/verify_urbis_lod2_source_batch.py",
    )
    audit = load_module(
        "urbis_batch_complexity",
        repo_root / "grand-bruxelles-game/tools/qa/audit_urbis_lod2_batch_complexity.py",
    )

    manifest, contract, selection = load_inputs(repo_root, manifest_path, selection_path)
    validate_selection(manifest, contract, selection)
    groups = shard_groups(selection, distribution_key)

    selected: list[str] = []
    group_by_owner: dict[str, dict[str, Any]] = {}
    for group in groups:
        for building_id in group["owner_ids"]:
            building_id = str(building_id)
            if building_id in group_by_owner:
                raise RuntimeError(f"owner duplicated inside shard: {building_id}")
            group_by_owner[building_id] = group
            selected.append(building_id)

    distribution_url = verifier.resolve_distribution(
        verifier.DEFAULT_FEED,
        distribution_key,
        contract["source"]["revision"],
    )
    package = verifier.http_get(distribution_url)
    package_sha256 = sha256_bytes(package)
    owners, solids_stats = verifier.read_owner_evidence(package)

    municipality_geometries: dict[str, Any] = {}
    for municipality in sorted({str(group["municipality"]) for group in groups}):
        feature = verifier.request_municipality_feature(municipality)
        geometry = shapely_shape(feature["geometry"])
        if geometry.is_empty or not geometry.is_valid:
            raise RuntimeError(f"official municipality geometry invalid/empty: {municipality}")
        municipality_geometries[municipality] = geometry

    solid_to_owner: dict[str, str] = {}
    for building_id in selected:
        owner = owners.get(building_id)
        if owner is None:
            raise RuntimeError(f"locked BU_ID {building_id} missing from official distribution")
        samples = int(owner["xy_samples"])
        if samples <= 0:
            raise RuntimeError(f"locked BU_ID {building_id} has no official XY sample")
        x = float(owner["sum_x"]) / samples
        y = float(owner["sum_y"]) / samples
        group = group_by_owner[building_id]
        if not verifier.inside_bbox(x, y, cell_bbox(str(group["cell_id"]))):
            raise RuntimeError(f"locked BU_ID {building_id} drifted outside {group['cell_id']}")
        municipality = str(group["municipality"])
        if not municipality_geometries[municipality].covers(Point(x, y)):
            raise RuntimeError(
                f"locked BU_ID {building_id} drifted outside official municipality {municipality}"
            )
        solid_ids = [str(value) for value in owner["solid_ids"]]
        if not solid_ids:
            raise RuntimeError(f"locked BU_ID {building_id} has no official solid ID")
        for solid_id in solid_ids:
            previous = solid_to_owner.setdefault(solid_id, building_id)
            if previous != building_id:
                raise RuntimeError(
                    f"solid {solid_id} maps to multiple selected owners: {previous}, {building_id}"
                )

    selected_urls = set(solid_to_owner)
    selected_numeric = {value.rsplit("/", 1)[-1] for value in selected_urls}
    matched_solids: set[str] = set()
    face_types: Counter[str] = Counter()
    face_count = 0
    point_count = 0
    part_count = 0
    payload_bytes = 0
    payload_hasher = hashlib.sha256()

    with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
        shp_name = audit.layer_member(archive, "buildingface", ".shp")
        dbf_name = audit.layer_member(archive, "buildingface", ".dbf")
        shx_name = audit.layer_member(archive, "buildingface", ".shx")
        if not shp_name or not dbf_name:
            raise RuntimeError("BuildingFaces SHP/DBF missing from official distribution")
        face_shp_sha256 = sha256_bytes(archive.read(shp_name))
        face_dbf_sha256 = sha256_bytes(archive.read(dbf_name))

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
            payload_hasher.update(line)
            payload_bytes += len(line)
            matched_solids.add(solid_id)
            face_types[raw_type] += 1
            face_count += 1
            point_count += points_here
            part_count += parts_here

    missing_solids = sorted(selected_urls - matched_solids)
    if missing_solids:
        raise RuntimeError(f"{len(missing_solids)} selected solid(s) have no BuildingFaces")

    report = {
        "schema": "grand-bruxelles-urbis-lod2-source-campaign-shard-v1",
        "campaign_id": manifest["campaign_id"],
        "distribution_key": distribution_key,
        "source": {
            "distribution_url": distribution_url,
            "revision": contract["source"]["revision"],
            "package_sha256": package_sha256,
            "building_solids_shp_sha256": solids_stats["building_solids_shp_sha256"],
            "building_solids_dbf_sha256": solids_stats["building_solids_dbf_sha256"],
            "building_faces_shp_sha256": face_shp_sha256,
            "building_faces_dbf_sha256": face_dbf_sha256,
            "crs": "EPSG:31370",
        },
        "selection": {
            "owner_count": len(selected),
            "owner_ids_sha256": owner_sequence_sha256(selected),
            "solid_count": len(selected_urls),
            "face_count": face_count,
            "point_count": point_count,
            "part_count": part_count,
            "face_type_counts": dict(sorted(face_types.items())),
            "municipalities": sorted({str(group["municipality"]) for group in groups}),
            "cells": sorted({str(group["cell_id"]) for group in groups}),
            "planner_groups": len(groups),
        },
        "canonical_payload": {
            "format": "canonical NDJSON digest only; original EPSG:31370 XYZ; one BuildingFace per line",
            "bytes": payload_bytes,
            "sha256": payload_hasher.hexdigest(),
            "artifact_geometry_written": False,
        },
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "geometry_modified": False,
        "semantic_names_authorized": False,
        "game_world_transform_authorized": False,
        "jouable_promotion_authorized": False,
    }

    expected = (manifest.get("source_shards") or {}).get(distribution_key)
    if expected is not None:
        comparable = {
            "source": report["source"],
            "selection": report["selection"],
            "canonical_payload": report["canonical_payload"],
        }
        if comparable != expected:
            raise RuntimeError(f"locked shard reproduction mismatch for {distribution_key}")

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "URBIS_LOD2_SOURCE_CAMPAIGN_SHARD_OK: "
        f"campaign={manifest['campaign_id']} distribution={distribution_key} "
        f"owners={len(selected)} solids={len(selected_urls)} faces={face_count} "
        f"bytes={payload_bytes} sha256={payload_hasher.hexdigest()} "
        f"locked={'yes' if expected is not None else 'measurement'}",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--distribution-key")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--lint-only", action="store_true")
    args = parser.parse_args()

    root = args.repo_root.resolve()
    try:
        manifest, contract, selection = load_inputs(
            root, args.manifest.resolve(), args.selection.resolve()
        )
        owners = validate_selection(manifest, contract, selection)
        if args.lint_only:
            print(
                "URBIS_LOD2_SOURCE_CAMPAIGN_SELECTION_OK: "
                f"campaign={manifest['campaign_id']} owners={len(owners)} "
                f"distributions={selection['distribution_count']} cells={selection['cell_count']} "
                f"sha256={selection['owner_sequence_sha256']}",
                flush=True,
            )
            return 0
        if not args.distribution_key or args.report is None:
            raise RuntimeError("--distribution-key and --report required unless --lint-only")
        verify_shard(
            root,
            args.manifest.resolve(),
            args.selection.resolve(),
            args.distribution_key,
            args.report.resolve(),
        )
    except Exception as exc:
        print(f"URBIS_LOD2_SOURCE_CAMPAIGN_SHARD_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
