#!/usr/bin/env python3
"""Aggregate the exhaustive C01 DTM shards using the exact official XYZ sample identity.

Recovery for PR #973. The prepare stage deduplicates GROUNDSURFACE vertices by
(owner, easting, northing, source_ground_z). Aggregation must preserve that same
identity: multiple official ground vertices may share XY while carrying distinct
source Z values. No source vertex is removed, merged, or warped here.
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import audit_region_lod2_c01_dtm_rigid_anchor as core


def aggregate_xyz(input_dir: Path, contract_path: Path, output_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    core.validate_hard_rules(contract)
    expected = contract["expected_source"]

    residual_files = sorted(input_dir.rglob("residuals_*.csv"))
    evidence_files = sorted(input_dir.rglob("dtm_evidence_*.json"))
    expected_tiles = int(expected["dtm_tile_count"])
    if len(residual_files) != expected_tiles or len(evidence_files) != expected_tiles:
        raise RuntimeError(
            f"expected {expected_tiles} residual/evidence files, "
            f"got {len(residual_files)}/{len(evidence_files)}"
        )

    evidence = [json.loads(path.read_text(encoding="utf-8")) for path in evidence_files]
    tiles = sorted(str(row["tile"]) for row in evidence)
    if tiles != list(expected["dtm_tiles"]):
        raise RuntimeError("aggregate DTM tile set drift")
    if any(row.get("runtime_authorized") is not False for row in evidence):
        raise RuntimeError("DTM evidence must remain runtime_authorized=false")
    if any(row.get("final_world_y_authorized") is not False for row in evidence):
        raise RuntimeError("DTM evidence must remain final_world_y_authorized=false")

    owner_residuals: dict[str, list[float]] = defaultdict(list)
    seen_xyz: set[tuple[str, str, str, str]] = set()
    xy_with_multiple_source_z: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    sample_count = 0

    for path in residual_files:
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                bid = str(row["building_id"])
                source_z = str(row["source_ground_z"])
                key_xyz = (bid, str(row["easting"]), str(row["northing"]), source_z)
                if key_xyz in seen_xyz:
                    raise RuntimeError(f"duplicate official XYZ ground sample: {key_xyz}")
                seen_xyz.add(key_xyz)
                xy_with_multiple_source_z[(bid, key_xyz[1], key_xyz[2])].add(source_z)
                owner_residuals[bid].append(float(row["residual_source_minus_dtm_m"]))
                sample_count += 1

    if len(owner_residuals) != int(expected["owners"]):
        raise RuntimeError(f"owners with residuals drift: {len(owner_residuals)}")
    if sample_count != int(expected["unique_ground_samples"]):
        raise RuntimeError(f"aggregate sample count drift: {sample_count}")
    if len(seen_xyz) != sample_count:
        raise RuntimeError("official XYZ identity accounting drift")

    multi_z_xy = sum(1 for values in xy_with_multiple_source_z.values() if len(values) > 1)
    if multi_z_xy <= 0:
        raise RuntimeError("expected source-backed same-XY / distinct-Z ground samples were not observed")

    baseline = [abs(value) for values in owner_residuals.values() for value in values]
    baseline_p95 = core.percentile(baseline, 0.95)
    policy = contract["policy"]
    deadband = float(policy["float_burial_deadband_m"])

    candidates: list[dict[str, Any]] = []
    candidate_rows: dict[float, list[dict[str, Any]]] = {}
    for raw_q in policy["candidate_quantiles"]:
        q = float(raw_q)
        summary, rows = core.evaluate_q(owner_residuals, q, deadband)
        candidates.append(summary)
        candidate_rows[q] = rows

    selected = min(
        candidates,
        key=lambda row: (
            float(row["post_residual_m"]["abs_p95"]),
            float(row["owner_max_abs_residual_m"]["p95"]),
            abs(float(row["quantile"]) - 0.5),
        ),
    )
    selected_q = float(selected["quantile"])
    if float(selected["post_residual_m"]["abs_p95"]) >= baseline_p95:
        raise RuntimeError("rigid owner anchor does not improve baseline p95")

    output_dir.mkdir(parents=True, exist_ok=True)
    selected_rows = candidate_rows[selected_q]
    fields = [
        "building_id",
        "sample_count",
        "rigid_shift_m",
        "post_residual_median_m",
        "post_residual_min_m",
        "post_residual_max_m",
        "post_max_abs_residual_m",
    ]
    with (output_dir / "rigid_anchor_selected_per_owner.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(selected_rows)

    owner_map = {
        row["building_id"]: {
            "rigid_shift_m": row["rigid_shift_m"],
            "sample_count": row["sample_count"],
            "post_max_abs_residual_m": row["post_max_abs_residual_m"],
        }
        for row in selected_rows
    }
    (output_dir / "rigid_anchor_selected_by_owner.json").write_text(
        json.dumps(owner_map, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )

    locks = {
        row["tile"]: {
            "url": row["url"],
            "archive_sha256": row["archive_sha256"],
            "raster_sha256": row["raster_sha256"],
            "samples": row["samples"],
            "raster_bounds": row.get("raster", {}).get("bounds"),
        }
        for row in evidence
    }
    (output_dir / "dtm_tile_locks.json").write_text(
        json.dumps(locks, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )

    report = {
        "schema": "grand-bruxelles-region-lod2-c01-dtm-rigid-anchor-measurement-v2",
        "campaign_id": contract["campaign_id"],
        "production_base_sha": contract["production_base_sha"],
        "sample_identity": "official_BU_ID+easting+northing+source_ground_z",
        "same_xy_distinct_source_z_sample_count": multi_z_xy,
        "input": {
            "owners": len(owner_residuals),
            "unique_ground_samples": sample_count,
            "dtm_tile_count": len(evidence),
            "baseline_vertex_abs_p95_m": baseline_p95,
        },
        "horizontal_transform": contract["horizontal_transform"],
        "policy": policy,
        "candidates": candidates,
        "selected_numerical_candidate": {
            "quantile": selected_q,
            "owner_count": len(selected_rows),
            "shift_m": selected["shift_m"],
            "post_residual_m": selected["post_residual_m"],
            "owner_max_abs_residual_m": selected["owner_max_abs_residual_m"],
            "runtime_authorized": False,
            "final_world_y_authorized": False,
        },
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "final_world_y_authorized": False,
        "terrain_runtime_authorized": False,
        "source_geometry_modified": False,
        "jouable_promotion_authorized": False,
        "artifact_only": True,
    }
    (output_dir / "dtm_rigid_anchor_measurement.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "C01_DTM_XYZ_AGGREGATE_OK: "
        f"q={selected_q:.2f} owners={len(selected_rows)} samples={sample_count} "
        f"same_xy_distinct_z={multi_z_xy} baseline_p95={baseline_p95:.9f} "
        f"post_p95={selected['post_residual_m']['abs_p95']:.9f} "
        "runtime_authorized=false"
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        aggregate_xyz(args.input_dir.resolve(), args.contract.resolve(), args.output_dir.resolve())
    except Exception as exc:
        print(f"C01_DTM_XYZ_AGGREGATE_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
