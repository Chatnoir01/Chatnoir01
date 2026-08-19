#!/usr/bin/env python3
"""Build the compact 30k LoD2 spatial streaming plan from immutable selection evidence."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import OrderedDict
from pathlib import Path

CELL_RE = re.compile(r"^E(-?\d+)_N(-?\d+)$")
POLICY_RE = re.compile(
    r"@export\s+var\s+(visual_load_radius_m|visual_unload_radius_m|collision_radius_m|"
    r"lookahead_seconds|max_operations_per_tick|max_active_cells)\s*:=\s*([0-9]+(?:\.[0-9]+)?)"
)
FIELDS = [
    "cell_id", "min_e", "min_n", "max_e", "max_n", "owner_count",
    "owner_sequence_sha256", "source_partition_count", "planner_group_count", "distribution_count",
]


def sequence_sha(values: list[str]) -> str:
    return hashlib.sha256(("\n".join(values) + "\n").encode()).hexdigest()


def policy_from_runtime(path: Path) -> dict[str, int | float]:
    values: dict[str, int | float] = {}
    for key, raw in POLICY_RE.findall(path.read_text(encoding="utf-8")):
        values[key] = float(raw) if "." in raw else int(raw)
    if len(values) != 6:
        raise RuntimeError(f"production streaming policy incomplete: {values}")
    if values["visual_unload_radius_m"] <= values["visual_load_radius_m"]:
        raise RuntimeError("unload radius must exceed load radius")
    return values


def build(selection: dict, runtime_policy: dict[str, int | float]) -> tuple[dict, list[dict]]:
    groups = selection.get("groups", [])
    if not groups:
        raise RuntimeError("selection groups missing")
    campaign_ids: list[str] = []
    partitions: set[tuple[str, str]] = set()
    revisions: set[str] = set()
    spatial: OrderedDict[str, dict] = OrderedDict()
    for group in groups:
        cell_id = str(group["cell_id"])
        match = CELL_RE.fullmatch(cell_id)
        if match is None:
            raise RuntimeError(f"bad planner cell id: {cell_id}")
        owner_ids = [str(value) for value in group["owner_ids"]]
        if not owner_ids or len(owner_ids) != len(set(owner_ids)):
            raise RuntimeError(f"bad owner group: {group['planner_batch_id']}")
        campaign_ids.extend(owner_ids)
        partitions.add((str(group["municipality_slug"]), cell_id))
        revisions.add(str(group["revision"]))
        cell = spatial.setdefault(cell_id, {"owner_ids": [], "partitions": set(), "groups": 0, "distributions": set()})
        cell["owner_ids"].extend(owner_ids)
        cell["partitions"].add((str(group["municipality_slug"]), cell_id))
        cell["groups"] += 1
        cell["distributions"].add(str(group["distribution_key"]))

    if len(campaign_ids) != int(selection["owner_count"]) or len(campaign_ids) != len(set(campaign_ids)):
        raise RuntimeError("campaign owner accounting drift")
    digest = sequence_sha(campaign_ids)
    if digest != str(selection["owner_sequence_sha256"]):
        raise RuntimeError("campaign owner sequence drift")
    if len(partitions) != int(selection["cell_count"]):
        raise RuntimeError("source partition accounting drift")
    if sum(int(v["groups"]) for v in spatial.values()) != int(selection["planner_group_count"]):
        raise RuntimeError("planner group accounting drift")
    if len(revisions) != 1:
        raise RuntimeError(f"multiple source revisions: {sorted(revisions)}")

    rows: list[dict] = []
    for cell_id, cell in spatial.items():
        match = CELL_RE.fullmatch(cell_id)
        east, north = int(match.group(1)), int(match.group(2))
        rows.append({
            "cell_id": cell_id,
            "min_e": east,
            "min_n": north,
            "max_e": east + 500,
            "max_n": north + 500,
            "owner_count": len(cell["owner_ids"]),
            "owner_sequence_sha256": sequence_sha(cell["owner_ids"]),
            "source_partition_count": len(cell["partitions"]),
            "planner_group_count": cell["groups"],
            "distribution_count": len(cell["distributions"]),
        })
    return {
        "schema": "grand-bruxelles-region-lod2-streaming-plan-v1",
        "campaign_id": str(selection["campaign_id"]),
        "source_revision": next(iter(revisions)),
        "campaign_owner_count": len(campaign_ids),
        "campaign_owner_sequence_sha256": digest,
        "source_partition_count": len(partitions),
        "spatial_cell_count": len(rows),
        "planner_group_count": int(selection["planner_group_count"]),
        "cell_size_m": 500,
        "spatial_cell_table": "generated CI artifact: region_lod2_C01_30000.streaming_cells.csv",
        "runtime_bridge": "res://game/scripts/brussels_world_streaming_runtime.gd",
        "streaming_policy": runtime_policy,
        "streaming_rules": {
            "single_campaign": True,
            "physical_cells_deduplicate_municipality_boundaries": True,
            "global_mount_forbidden": True,
            "source_geometry_modified": False,
        },
        "authorization": {
            "source_registered": True,
            "streaming_plan_authorized": True,
            "geometry_materialization_authorized": False,
            "game_world_transform_authorized": False,
            "runtime_mount_authorized": False,
            "collision_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }, rows


def write_outputs(summary: dict, rows: list[dict], summary_out: Path, cells_out: Path) -> None:
    cells_out.parent.mkdir(parents=True, exist_ok=True)
    with cells_out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    summary["spatial_cell_table_sha256"] = hashlib.sha256(cells_out.read_bytes()).hexdigest()
    summary_out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--runtime-script", type=Path, required=True)
    parser.add_argument("--summary-out", type=Path, required=True)
    parser.add_argument("--cells-out", type=Path, required=True)
    args = parser.parse_args()
    selection = json.loads(args.selection.read_text(encoding="utf-8"))
    summary, rows = build(selection, policy_from_runtime(args.runtime_script))
    write_outputs(summary, rows, args.summary_out, args.cells_out)
    print(
        "REGION_LOD2_C01_STREAMING_PLAN_BUILT: "
        f"owners={summary['campaign_owner_count']} source_partitions={summary['source_partition_count']} "
        f"spatial_cells={summary['spatial_cell_count']} groups={summary['planner_group_count']} "
        f"active_cap={summary['streaming_policy']['max_active_cells']} "
        f"ops_per_tick={summary['streaming_policy']['max_operations_per_tick']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
