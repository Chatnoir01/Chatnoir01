#!/usr/bin/env python3
"""Build immutable C02 30k selection from the locked regional planner artifact.

C02 never scans mutable repository persistence. It first reconstructs C01 exactly
from the same immutable planner evidence and requires C01's locked digest. It then
selects all remaining single-distribution Bruxelles owners (excluding the already
persisted Grand-Place IDs), followed by Uccle in planner batch order until 30,000.

Evidence/source-registry only: runtime/mount/collision/visual authorization stays false.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def owner_ids(row: dict[str, str]) -> list[str]:
    return [value for value in str(row["building_ids"]).split(";") if value]


def sha256_owner_sequence(values: list[str]) -> str:
    return hashlib.sha256(("\n".join(values) + "\n").encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--planner-dir", type=Path, required=True)
    parser.add_argument("--selection-out", type=Path, required=True)
    parser.add_argument("--matrix-out", type=Path, required=True)
    args = parser.parse_args()

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    policy = contract["selection_policy"]
    expected = contract["expected"]
    predecessor = contract["predecessor_campaign"]
    target = int(contract["target_owner_count"])
    revision = str(contract["source"]["revision"])

    batches = read_csv(args.planner_dir / "source_batches.csv")
    assignments = read_csv(args.planner_dir / "missing_owner_assignments.csv")
    assignment_by_id = {str(row["building_id"]): row for row in assignments}

    gp_ids = set(map(str, policy["bruxelles_already_persisted_grand_place_ids"]))
    c01_skip_batches = set(policy["c01_already_registered_anderlecht_batches"])

    def validate_owner(building_id: str, municipality_slug: str) -> dict[str, str] | None:
        evidence = assignment_by_id.get(building_id)
        if evidence is None:
            raise RuntimeError(f"planner assignment missing for BU_ID {building_id}")
        if evidence["assignment_status"] != "assigned":
            raise RuntimeError(f"BU_ID {building_id} is not planner-assigned")
        if evidence["municipality_slug"] != municipality_slug:
            raise RuntimeError(
                f"BU_ID {building_id} municipality drift: "
                f"{evidence['municipality_slug']} != {municipality_slug}"
            )
        if str(evidence["revision_dates"]) != revision:
            raise RuntimeError(f"BU_ID {building_id} revision drift")
        if ";" in str(evidence["distribution_keys"]):
            return None
        return evidence

    c01: list[str] = []
    for batch in batches:
        if batch["assignment_status"] != "assigned" or batch["municipality_slug"] != "anderlecht":
            continue
        if batch["batch_id"] in c01_skip_batches:
            continue
        for building_id in owner_ids(batch):
            if validate_owner(building_id, "anderlecht") is None:
                raise RuntimeError(f"C01 Anderlecht unexpectedly multi-distribution: {building_id}")
            c01.append(building_id)

    for batch in batches:
        if len(c01) >= int(predecessor["owner_count"]):
            break
        if batch["assignment_status"] != "assigned" or batch["municipality_slug"] != "bruxelles":
            continue
        for building_id in owner_ids(batch):
            if len(c01) >= int(predecessor["owner_count"]):
                break
            if building_id in gp_ids:
                continue
            if validate_owner(building_id, "bruxelles") is None:
                continue
            c01.append(building_id)

    if len(c01) != int(predecessor["owner_count"]):
        raise RuntimeError(f"C01 reconstruction count drift: {len(c01)}")
    c01_digest = sha256_owner_sequence(c01)
    if c01_digest != predecessor["owner_sequence_sha256"]:
        raise RuntimeError(f"C01 reconstruction digest drift: {c01_digest}")
    c01_set = set(c01)

    rows: list[dict[str, Any]] = []
    sequence = 1

    def append_owner(batch: dict[str, str], building_id: str, municipality_slug: str) -> bool:
        nonlocal sequence
        evidence = validate_owner(building_id, municipality_slug)
        if evidence is None:
            return False
        rows.append({
            "sequence": sequence,
            "building_id": building_id,
            "municipality_slug": municipality_slug,
            "municipality": evidence["municipality"],
            "cell_id": evidence["cell_id"],
            "planner_batch_id": batch["batch_id"],
            "distribution_key": evidence["distribution_keys"],
            "revision": evidence["revision_dates"],
        })
        sequence += 1
        return True

    for municipality_slug in ["bruxelles", "uccle"]:
        for batch in batches:
            if len(rows) >= target:
                break
            if batch["assignment_status"] != "assigned" or batch["municipality_slug"] != municipality_slug:
                continue
            for building_id in owner_ids(batch):
                if len(rows) >= target:
                    break
                if building_id in c01_set:
                    continue
                if municipality_slug == "bruxelles" and building_id in gp_ids:
                    continue
                append_owner(batch, building_id, municipality_slug)
        if len(rows) >= target:
            break

    if len(rows) != target:
        raise RuntimeError(f"campaign target not reached: {len(rows)} != {target}")

    groups: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for row in rows:
        key = (row["planner_batch_id"], row["distribution_key"])
        if current is None or (current["planner_batch_id"], current["distribution_key"]) != key:
            current = {
                "planner_batch_id": row["planner_batch_id"],
                "municipality_slug": row["municipality_slug"],
                "municipality": row["municipality"],
                "cell_id": row["cell_id"],
                "distribution_key": row["distribution_key"],
                "revision": row["revision"],
                "owner_ids": [],
            }
            groups.append(current)
        current["owner_ids"].append(row["building_id"])

    flattened = [building_id for group in groups for building_id in group["owner_ids"]]
    if flattened != [row["building_id"] for row in rows]:
        raise RuntimeError("group construction changed campaign owner sequence")
    if len(flattened) != len(set(flattened)):
        raise RuntimeError("campaign selection contains duplicate owners")
    if set(flattened) & c01_set:
        raise RuntimeError("C02 overlaps predecessor C01")

    municipality_counts = Counter(row["municipality"] for row in rows)
    distributions = sorted({row["distribution_key"] for row in rows})
    cells = {(row["municipality"], row["cell_id"]) for row in rows}
    digest = sha256_owner_sequence(flattened)

    observed = {
        "owner_count": len(rows),
        "municipality_counts": dict(municipality_counts),
        "distribution_count": len(distributions),
        "cell_count": len(cells),
        "planner_group_count": len(groups),
        "owner_sequence_sha256": digest,
    }
    for key, value in observed.items():
        if value != expected[key]:
            raise RuntimeError(f"campaign selection drift for {key}: {value!r} != {expected[key]!r}")

    selection = {
        "schema": "grand-bruxelles-urbis-lod2-source-campaign-selection-v1",
        "campaign_id": contract["campaign_id"],
        "planner_artifact_id": contract["planning_evidence"]["planner_artifact_id"],
        "planner_artifact_sha256": contract["planning_evidence"]["planner_artifact_sha256"],
        "predecessor_campaign_id": predecessor["campaign_id"],
        "predecessor_owner_sequence_sha256": c01_digest,
        "owner_count": len(rows),
        "owner_sequence_sha256": digest,
        "municipality_counts": dict(municipality_counts),
        "distribution_count": len(distributions),
        "cell_count": len(cells),
        "planner_group_count": len(groups),
        "first_sequence_owner": rows[0]["building_id"],
        "last_sequence_owner": rows[-1]["building_id"],
        "groups": groups,
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "geometry_modified": False,
        "semantic_names_authorized": False,
        "game_world_transform_authorized": False,
        "jouable_promotion_authorized": False,
    }

    matrix = []
    for distribution in distributions:
        token = distribution.split("_")[-2]
        matrix.append({"tile": token, "distribution": distribution})

    args.selection_out.parent.mkdir(parents=True, exist_ok=True)
    args.selection_out.write_text(json.dumps(selection, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    args.matrix_out.write_text(json.dumps({"include": matrix}, separators=(",", ":")) + "\n", encoding="utf-8")
    print(
        "REGION_LOD2_C02_SELECTION_OK: "
        f"owners={len(rows)} bruxelles={municipality_counts['Bruxelles']} "
        f"uccle={municipality_counts['Uccle']} distributions={len(distributions)} "
        f"cells={len(cells)} groups={len(groups)} sha256={digest}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
