#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"expected JSON object: {path}")
    return data


def by_name(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        name = str(row.get("animation_name", ""))
        if not name or name in out:
            raise RuntimeError(f"invalid or duplicate animation name: {name!r}")
        out[name] = row
    return out


def close(actual: float, expected: float, tol: float = 1e-5) -> bool:
    return math.isfinite(actual) and abs(actual - expected) <= tol


def validate(inventory: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    if inventory.get("format") != "grand-bruxelles-gate8-variant01-source-arm-swing-inventory-v1":
        raise RuntimeError("inventory format drift")
    if inventory.get("diagnostic_state") != "SOURCE_ARM_SWING_INVENTORY_COMPLETE":
        raise RuntimeError("inventory is not complete")
    if inventory.get("failures") != []:
        raise RuntimeError("inventory reports failures")
    expected_count = int(contract["inventory_animation_count"])
    rows = inventory.get("clips")
    if not isinstance(rows, list) or len(rows) != expected_count or int(inventory.get("animation_count", -1)) != expected_count:
        raise RuntimeError("inventory animation count drift")
    if inventory.get("walk_alias_selected") != "" or inventory.get("run_alias_selected") != "":
        raise RuntimeError("inventory unexpectedly selected an alias")
    for key in ("production_authorized", "activation_ready", "adoption_ready"):
        if inventory.get(key) is not False:
            raise RuntimeError(f"inventory rail opened: {key}")

    named = by_name(rows)
    semantic = contract.get("normal_walk_semantic_candidates")
    if not isinstance(semantic, list) or [str(row.get("animation_name")) for row in semantic] != ["Walk", "Walk_Formal"]:
        raise RuntimeError("normal-walk semantic review set drift")

    measured: dict[str, float] = {}
    for lock in semantic:
        name = str(lock["animation_name"])
        row = named.get(name)
        if row is None:
            raise RuntimeError(f"reviewed walk clip missing from complete inventory: {name}")
        actual = float(row["max_upper_arm_swing_deg"])
        expected = float(lock["max_upper_arm_swing_deg"])
        if not close(actual, expected):
            raise RuntimeError(f"authored swing drift for {name}: {actual} vs {expected}")
        measured[name] = actual

    examples = contract.get("lower_swing_non_walk_examples")
    if not isinstance(examples, list) or not examples:
        raise RuntimeError("lower-swing non-walk evidence missing")
    for lock in examples:
        name = str(lock["animation_name"])
        reason = str(lock.get("reason", ""))
        if not reason:
            raise RuntimeError(f"missing non-walk reason for {name}")
        row = named.get(name)
        if row is None:
            raise RuntimeError(f"non-walk evidence clip missing: {name}")
        actual = float(row["max_upper_arm_swing_deg"])
        if not close(actual, float(lock["max_upper_arm_swing_deg"])):
            raise RuntimeError(f"non-walk evidence swing drift for {name}")

    threshold = float(contract["low_swing_review_threshold_deg"])
    low_swing_names = sorted(
        name for name, row in named.items() if float(row["max_upper_arm_swing_deg"]) < threshold
    )
    reviewed_normal_walk_below_threshold = sorted(
        name for name in ("Walk", "Walk_Formal") if measured[name] < threshold
    )
    if reviewed_normal_walk_below_threshold:
        raise RuntimeError(f"normal walk unexpectedly fell below review threshold: {reviewed_normal_walk_below_threshold}")

    if contract.get("catalog_conclusion") != "NO_LOWER_SWING_SEMANTIC_NORMAL_WALK_IN_PINNED_SOURCE":
        raise RuntimeError("catalog conclusion drift")
    if contract.get("library_rejected_globally") is not False:
        raise RuntimeError("source library must not be globally rejected")
    if contract.get("walk_slot_blocked_for_variant01_target_skin") is not True:
        raise RuntimeError("variant-01 walk-slot blocker must remain explicit")
    if contract.get("walk_alias_selected") != "" or contract.get("run_alias_selected") != "":
        raise RuntimeError("contract unexpectedly selected locomotion aliases")
    if int(contract.get("dynamic_garder_count", -1)) != 0:
        raise RuntimeError("dynamic GARDER must remain zero")
    for key in ("production_authorized", "activation_ready", "adoption_ready"):
        if contract.get(key) is not False:
            raise RuntimeError(f"contract rail opened: {key}")

    return {
        "animation_count": expected_count,
        "walk_swing_deg": measured["Walk"],
        "walk_formal_swing_deg": measured["Walk_Formal"],
        "low_swing_clip_names": low_swing_names,
        "normal_walk_below_threshold": reviewed_normal_walk_below_threshold,
        "conclusion": contract["catalog_conclusion"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = validate(load_json(args.inventory), load_json(args.contract))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GATE8_SOURCE_CATALOG_WALK_EXHAUSTION_OK "
        f"animations={result['animation_count']} walk={result['walk_swing_deg']:.6f} "
        f"walk_formal={result['walk_formal_swing_deg']:.6f} "
        f"low_swing={','.join(result['low_swing_clip_names'])} alias_selected=false production_authorized=false"
    )


if __name__ == "__main__":
    main()
