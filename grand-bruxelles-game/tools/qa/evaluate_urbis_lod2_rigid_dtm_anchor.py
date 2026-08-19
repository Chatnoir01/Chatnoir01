#!/usr/bin/env python3
"""Evaluate rigid per-owner DTM anchor translations for a measured LoD2 batch.

Consumes the ground-vertex residual CSV from the official DTM alignment audit.
Every tested policy applies one scalar vertical translation to an entire BU_ID;
no source vertex is warped. Results are evidence-only and cannot authorize final
world Y, runtime mounting, terrain runtime or collisions.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Any


def percentile(values: list[float], q: float) -> float:
    if not values:
        raise RuntimeError("percentile requires non-empty values")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * q
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def load_residuals(path: Path) -> dict[str, list[float]]:
    owners: dict[str, list[float]] = defaultdict(list)
    with path.open("r", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            building_id = str(row.get("building_id") or "").strip()
            if not building_id.isdigit():
                raise RuntimeError(f"invalid building_id in residual CSV: {building_id!r}")
            residual = float(row["residual_source_minus_dtm_m"])
            if not math.isfinite(residual):
                raise RuntimeError(f"non-finite residual for {building_id}")
            owners[building_id].append(residual)
    if not owners:
        raise RuntimeError("residual CSV contains no owners")
    return owners


def policy_metrics(owners: dict[str, list[float]], q: float, deadband: float):
    all_post: list[float] = []
    shifts: list[float] = []
    owner_max_abs: list[float] = []
    owner_rows: list[dict[str, Any]] = []

    for building_id in sorted(owners, key=int):
        residuals = owners[building_id]
        terrain_minus_source = [-value for value in residuals]
        shift = percentile(terrain_minus_source, q)
        post = [value + shift for value in residuals]
        abs_post = [abs(value) for value in post]
        max_abs = max(abs_post)
        shifts.append(shift)
        all_post.extend(post)
        owner_max_abs.append(max_abs)
        owner_rows.append({
            "building_id": building_id,
            "quantile": q,
            "sample_count": len(residuals),
            "rigid_shift_m": shift,
            "post_residual_median_m": statistics.median(post),
            "post_residual_min_m": min(post),
            "post_residual_max_m": max(post),
            "post_max_abs_residual_m": max_abs,
        })

    abs_all = [abs(value) for value in all_post]
    positive = sum(1 for value in all_post if value > deadband)
    negative = sum(1 for value in all_post if value < -deadband)
    neutral = len(all_post) - positive - negative
    metrics = {
        "quantile": q,
        "owners": len(owners),
        "samples": len(all_post),
        "shift_m": {
            "min": min(shifts),
            "median": statistics.median(shifts),
            "max": max(shifts),
            "p90": percentile(shifts, 0.90),
            "p95": percentile(shifts, 0.95),
        },
        "post_residual_m": {
            "mean": statistics.fmean(all_post),
            "median": statistics.median(all_post),
            "min": min(all_post),
            "max": max(all_post),
            "abs_p50": percentile(abs_all, 0.50),
            "abs_p90": percentile(abs_all, 0.90),
            "abs_p95": percentile(abs_all, 0.95),
            "abs_p99": percentile(abs_all, 0.99),
            "abs_max": max(abs_all),
            "within_0_25m": sum(1 for value in abs_all if value <= 0.25),
            "within_0_50m": sum(1 for value in abs_all if value <= 0.50),
            "within_1m": sum(1 for value in abs_all if value <= 1.0),
            "positive_over_deadband": positive,
            "negative_below_deadband": negative,
            "within_deadband": neutral,
            "positive_fraction": positive / len(all_post),
            "negative_fraction": negative / len(all_post),
        },
        "owner_max_abs_residual_m": {
            "p50": percentile(owner_max_abs, 0.50),
            "p90": percentile(owner_max_abs, 0.90),
            "p95": percentile(owner_max_abs, 0.95),
            "p99": percentile(owner_max_abs, 0.99),
            "max": max(owner_max_abs),
        },
    }
    return metrics, owner_rows


def select_candidate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    def key(row: dict[str, Any]):
        return (
            float(row["post_residual_m"]["abs_p95"]),
            float(row["owner_max_abs_residual_m"]["p95"]),
            abs(float(row["quantile"]) - 0.5),
        )
    return min(rows, key=key)


def run(residuals_path: Path, contract_path: Path, output_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "final_world_y_authorized", "terrain_runtime_authorized", "source_geometry_modified",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")
    if hard.get("owner_rigid_translation_only") is not True:
        raise RuntimeError("contract must require owner_rigid_translation_only=true")
    if hard.get("artifact_only") is not True:
        raise RuntimeError("contract must remain artifact_only=true")
    policy = contract["policy"]
    if policy.get("source_vertex_warping_allowed") is not False:
        raise RuntimeError("source vertex warping must remain forbidden")
    if policy.get("authorization_threshold") is not None:
        raise RuntimeError("candidate comparison must not contain an authorization threshold")

    owners = load_residuals(residuals_path)
    expected = contract["expected_input"]
    sample_count = sum(len(values) for values in owners.values())
    if len(owners) != int(expected["owners"]):
        raise RuntimeError(f"owner count drift: {len(owners)}")
    if sample_count != int(expected["ground_vertex_samples"]):
        raise RuntimeError(f"sample count drift: {sample_count}")

    baseline_abs = [abs(value) for values in owners.values() for value in values]
    baseline_p95 = percentile(baseline_abs, 0.95)
    if abs(baseline_p95 - float(expected["unshifted_vertex_abs_p95_m"])) > 0.000001:
        raise RuntimeError(
            f"baseline p95 drift: expected {expected['unshifted_vertex_abs_p95_m']}, got {baseline_p95}"
        )

    deadband = float(policy["float_burial_deadband_m"])
    summaries: list[dict[str, Any]] = []
    owner_rows: list[dict[str, Any]] = []
    for raw_q in policy["candidate_quantiles"]:
        q = float(raw_q)
        if q < 0.0 or q > 1.0:
            raise RuntimeError(f"invalid quantile {q}")
        summary, rows = policy_metrics(owners, q, deadband)
        summaries.append(summary)
        owner_rows.extend(rows)

    selected = select_candidate(summaries)
    if float(selected["post_residual_m"]["abs_p95"]) >= baseline_p95:
        raise RuntimeError("selected rigid anchor candidate does not improve vertex abs p95")

    output_dir.mkdir(parents=True, exist_ok=True)
    with (output_dir / "rigid_anchor_per_owner.csv").open("w", newline="", encoding="utf-8") as handle:
        fields = [
            "building_id", "quantile", "sample_count", "rigid_shift_m",
            "post_residual_median_m", "post_residual_min_m", "post_residual_max_m",
            "post_max_abs_residual_m",
        ]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(owner_rows)

    report = {
        "schema": "grand-bruxelles-urbis-lod2-rigid-anchor-evaluation-v1",
        "batch_id": contract["batch_id"],
        "input": {
            "owners": len(owners),
            "ground_vertex_samples": sample_count,
            "unshifted_vertex_abs_p95_m": baseline_p95,
        },
        "policy": policy,
        "candidates": summaries,
        "selected_numerical_candidate": {
            "quantile": selected["quantile"],
            "selection_metric": policy["selection_metric"],
            "post_residual_m": selected["post_residual_m"],
            "shift_m": selected["shift_m"],
            "owner_max_abs_residual_m": selected["owner_max_abs_residual_m"],
            "runtime_authorized": False,
            "final_world_y_authorized": False,
        },
        "interpretation": {
            "selected_policy_authorized": False,
            "global_vertical_origin_resolved": False,
            "terrain_mesh_required_before_runtime": True,
            "note": "The numerical winner only minimizes the declared residual metric among tested rigid owner translations. Visual, terrain-seam, door/ground-contact and global vertical-origin gates remain required."
        },
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "final_world_y_authorized": False,
        "terrain_runtime_authorized": False,
        "source_geometry_modified": False,
        "artifact_only": True,
    }
    (output_dir / "rigid_anchor_evaluation.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "URBIS_LOD2_B01_RIGID_ANCHOR_EVALUATED: "
        f"candidates={len(summaries)} selected_q={selected['quantile']} "
        f"baseline_abs_p95={baseline_p95:.6f} "
        f"selected_abs_p95={selected['post_residual_m']['abs_p95']:.6f} "
        f"selected_shift_median={selected['shift_m']['median']:.6f} "
        "runtime_authorized=false",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--residuals", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.residuals.resolve(), args.contract.resolve(), args.output_dir.resolve())
    except Exception as exc:
        print(f"URBIS_LOD2_B01_RIGID_ANCHOR_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
