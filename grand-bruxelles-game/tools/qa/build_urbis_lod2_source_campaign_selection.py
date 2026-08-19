#!/usr/bin/env python3
"""Build the immutable 30k campaign selection from the locked planner artifact.

The planner artifact itself is immutable evidence (artifact id + SHA locked in the
campaign contract). This tool never rescans mutable repository persistence state.
It deterministically:
1. takes every planner-assigned Anderlecht owner except already-registered B01-B03;
2. then takes planner-assigned Bruxelles owners until the campaign reaches 30,000;
3. skips the explicitly already-persisted Grand-Place IDs;
4. skips owners whose planner evidence spans multiple source distributions.

The generated selection is CI evidence only. Runtime/mount/collision/visual
authorization remains false.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


def sha256_owner_sequence(owner_ids: list[str]) -> str:
    payload = ("\n".join(owner_ids) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def owner_ids(row: dict[str, str]) -> list[str]:
    return [value for value in str(row["building_ids"]).split(";") if value]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--planner-dir", type=Path, required=True)
    parser.add_argument("--selection-out", type=Path, required=True)
    parser.add_argument("--matrix-out", type=Path, required=True)
    args = parser.parse_args()

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    expected = contract["expected"]
    policy = contract["selection_policy"]
    target = int(contract["target_owner_count"])

    batches = read_csv(args.planner_dir / "source_batches.csv")
    assignments = read_csv(args.planner_dir / "missing_owner_assignments.csv")
    assignment_by_id = {str(row["building_id"]): row for row in assignments}

    skip_batches = set(policy["already_registered_anderlecht_batches"])
    skip_bruxelles_ids = set(map(str, policy["bruxelles_already_persisted_grand_place_ids"]))

    rows: list[dict[str, Any]] = []
    sequence = 1

    def append_owner(batch: dict[str, str], building_id: str, municipality_slug: str) -> bool:
        nonlocal sequence
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
        distributions = str(evidence["distribution_keys"])
        if ";" in distributions:
            return False
        if str(evidence["revision_dates"]) != str(contract["source"]["revision"]):
            raise RuntimeError(f"BU_ID {building_id} revision drift")
        rows.append({
            "sequence": sequence,
            "building_id": building_id,
            "municipality_slug": municipality_slug,
            "municipality": evidence["municipality"],
            "cell_id": evidence["cell_id"],
            "planner_batch_id": batch["batch_id"],
            "distribution_key": distributions,
            "revision": evidence["revision_dates"],
        })
        sequence += 1
        return True

    for batch in batches:
        if batch["assignment_status"] != "assigned":
            continue
        if batch["municipality_slug"] != "anderlecht":
            continue
        if batch["batch_id"] in skip_batches:
            continue
        for building_id in owner_ids(batch):
            if not append_owner(batch, building_id, "anderlecht"):
                raise RuntimeError(
                    f"Anderlecht campaign unexpectedly contains multi-distribution owner {building_id}"
                )

    anderlecht_count = len(rows)

    for batch in batches:
        if len(rows) >= target:
            break
        if batch["assignment_status"] != "assigned":
            continue
        if batch["municipality_slug"] != "bruxelles":
            continue
        for building_id in owner_ids(batch):
            if len(rows) >= target:
                break
            if building_id in skip_bruxelles_ids:
                continue
            append_owner(batch, building_id, "bruxelles")

    if len(rows) != target:
        raise RuntimeError(f"campaign target not reached: {len(rows)} != {target}")

    groups: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for row in rows:
        key = (row["planner_batch_id"], row["distribution_key"])
        if current is None or (
            current["planner_batch_id"], current["distribution_key"]
        ) != key:
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

    if anderlecht_count != int(expected["municipality_counts"]["Anderlecht"]):
        raise RuntimeError("Anderlecht remainder count drift")

    selection = {
        "schema": "grand-bruxelles-urbis-lod2-source-campaign-selection-v1",
        "campaign_id": contract["campaign_id"],
        "planner_artifact_id": contract["planning_evidence"]["planner_artifact_id"],
        "planner_artifact_sha256": contract["planning_evidence"]["planner_artifact_sha256"],
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
    args.selection_out.write_text(
        json.dumps(selection, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    args.matrix_out.write_text(
        json.dumps({"include": matrix}, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "REGION_LOD2_C01_SELECTION_OK: "
        f"owners={len(rows)} anderlecht={municipality_counts['Anderlecht']} "
        f"bruxelles={municipality_counts['Bruxelles']} distributions={len(distributions)} "
        f"cells={len(cells)} groups={len(groups)} sha256={digest}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
