#!/usr/bin/env python3
"""Validate locked C01 selection/source evidence and build materialization matrices."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import OrderedDict
from pathlib import Path
from typing import Any

TILE_RE = re.compile(r"shp_(\d{6})_\{date\}\.zip$", re.I)
CELL_RE = re.compile(r"^E(-?\d+)_N(-?\d+)$")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def owner_sequence_sha256(values: list[str]) -> str:
    return sha256_bytes(("\n".join(values) + "\n").encode("utf-8"))


def validate(selection: dict[str, Any], summary: dict[str, Any], contract: dict[str, Any]) -> tuple[list[dict[str, str]], list[dict[str, Any]]]:
    expected = contract["expected"]
    if selection.get("campaign_id") != contract["campaign_id"] or summary.get("campaign_id") != contract["campaign_id"]:
        raise RuntimeError("campaign ID mismatch")
    if summary.get("status") != "locked-exact":
        raise RuntimeError("source summary must be locked-exact")
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "geometry_modified", "game_world_transform_authorized", "jouable_promotion_authorized",
    ]:
        if selection.get(key) is not False or summary.get(key) is not False:
            raise RuntimeError(f"locked evidence must keep {key}=false")
    hard = contract["hard_rules"]
    if hard.get("artifact_source_materialization_only") is not True:
        raise RuntimeError("artifact source materialization must be explicit")
    if hard.get("source_geometry_modified") is not False:
        raise RuntimeError("source geometry modification must remain false")
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "game_world_transform_authorized", "jouable_promotion_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")

    if int(selection["owner_count"]) != int(expected["owner_count"]):
        raise RuntimeError("owner count drift")
    if selection["owner_sequence_sha256"] != expected["owner_sequence_sha256"]:
        raise RuntimeError("owner sequence drift")
    metrics = summary["metrics"]
    for key in ["owner_count", "solid_count", "face_count", "point_count", "part_count", "canonical_payload_bytes", "source_shard_count"]:
        if int(metrics[key]) != int(expected[key]):
            raise RuntimeError(f"summary metric drift: {key}")
    if metrics["source_shards_sha256"] != expected["source_shards_sha256"]:
        raise RuntimeError("source shard digest drift")
    if metrics["face_type_counts"] != expected["face_type_counts"]:
        raise RuntimeError("face type metrics drift")

    groups = selection["groups"]
    campaign_ids: list[str] = []
    distributions: OrderedDict[str, dict[str, Any]] = OrderedDict()
    cells: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for group in groups:
        ids = [str(value) for value in group["owner_ids"]]
        if not ids or len(ids) != len(set(ids)):
            raise RuntimeError(f"bad planner group: {group['planner_batch_id']}")
        campaign_ids.extend(ids)
        distribution_key = str(group["distribution_key"])
        shard = distributions.setdefault(
            distribution_key,
            {"owner_ids": [], "cells": set(), "municipalities": set(), "groups": 0},
        )
        shard["owner_ids"].extend(ids)
        shard["cells"].add(str(group["cell_id"]))
        shard["municipalities"].add(str(group["municipality"]))
        shard["groups"] += 1

        cell_id = str(group["cell_id"])
        if CELL_RE.fullmatch(cell_id) is None:
            raise RuntimeError(f"invalid cell ID: {cell_id}")
        cell = cells.setdefault(
            cell_id,
            {"owner_ids": [], "distributions": set(), "municipalities": set(), "groups": 0},
        )
        cell["owner_ids"].extend(ids)
        cell["distributions"].add(distribution_key)
        cell["municipalities"].add(str(group["municipality"]))
        cell["groups"] += 1

    if len(campaign_ids) != int(expected["owner_count"]) or len(campaign_ids) != len(set(campaign_ids)):
        raise RuntimeError("campaign owner accounting drift")
    if owner_sequence_sha256(campaign_ids) != expected["owner_sequence_sha256"]:
        raise RuntimeError("campaign owner digest drift")
    if len(distributions) != int(expected["source_shard_count"]):
        raise RuntimeError("distribution count drift")
    if len(cells) != int(expected["spatial_cell_count"]):
        raise RuntimeError("physical cell count drift")
    if sum(v["groups"] for v in cells.values()) != int(expected["planner_group_count"]):
        raise RuntimeError("planner group count drift")

    matrix: list[dict[str, str]] = []
    locked_shards = summary["source_shards"]
    for distribution_key, shard in distributions.items():
        locked = locked_shards.get(distribution_key)
        if not isinstance(locked, dict):
            raise RuntimeError(f"distribution missing from locked summary: {distribution_key}")
        locked_selection = locked["selection"]
        if len(shard["owner_ids"]) != int(locked_selection["owner_count"]):
            raise RuntimeError(f"owner count drift for {distribution_key}")
        if owner_sequence_sha256(shard["owner_ids"]) != locked_selection["owner_ids_sha256"]:
            raise RuntimeError(f"owner digest drift for {distribution_key}")
        if sorted(shard["cells"]) != list(locked_selection["cells"]):
            raise RuntimeError(f"cell drift for {distribution_key}")
        if sorted(shard["municipalities"]) != list(locked_selection["municipalities"]):
            raise RuntimeError(f"municipality drift for {distribution_key}")
        if shard["groups"] != int(locked_selection["planner_groups"]):
            raise RuntimeError(f"planner group drift for {distribution_key}")
        match = TILE_RE.search(distribution_key)
        if match is None:
            raise RuntimeError(f"cannot derive tile from {distribution_key}")
        matrix.append({"distribution_key": distribution_key, "tile": match.group(1)})

    cell_rows: list[dict[str, Any]] = []
    for cell_id, cell in cells.items():
        owners = cell["owner_ids"]
        cell_rows.append({
            "cell_id": cell_id,
            "owner_count": len(owners),
            "owner_sequence_sha256": owner_sequence_sha256(owners),
            "distribution_count": len(cell["distributions"]),
            "distributions": ",".join(sorted(cell["distributions"])),
            "municipality_count": len(cell["municipalities"]),
            "municipalities": ",".join(sorted(cell["municipalities"])),
            "planner_group_count": cell["groups"],
        })
    return matrix, cell_rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--matrix-out", type=Path, required=True)
    parser.add_argument("--cells-out", type=Path, required=True)
    args = parser.parse_args()
    try:
        selection = json.loads(args.selection.read_text(encoding="utf-8"))
        summary = json.loads(args.summary.read_text(encoding="utf-8"))
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        matrix, cells = validate(selection, summary, contract)
        args.matrix_out.write_text(
            json.dumps({"include": matrix}, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        args.cells_out.parent.mkdir(parents=True, exist_ok=True)
        fields = [
            "cell_id", "owner_count", "owner_sequence_sha256", "distribution_count",
            "distributions", "municipality_count", "municipalities", "planner_group_count",
        ]
        with args.cells_out.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(cells)
        print(
            "REGION_LOD2_C01_SOURCE_MATERIALIZATION_PLAN_OK: "
            f"owners={contract['expected']['owner_count']} shards={len(matrix)} cells={len(cells)}"
        )
    except Exception as exc:
        print(f"REGION_LOD2_C01_SOURCE_MATERIALIZATION_PLAN_ERROR: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
