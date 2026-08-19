#!/usr/bin/env python3
"""Lock and reproduce the exhaustive C01 30k rigid DTM anchor measurement.

Consumes the 48 already source-verified DTM shard outputs from #973. Official
GROUNDSURFACE sample identity is (BU_ID, easting, northing, source_ground_z).
No source vertex is removed, merged, warped, or runtime-authorized.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(values: list[float], q: float) -> float:
    if not values:
        raise RuntimeError("percentile requires non-empty values")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = (len(ordered) - 1) * q
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    weight = pos - lo
    return ordered[lo] * (1.0 - weight) + ordered[hi] * weight


def validate_contract(contract: dict[str, Any]) -> None:
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "final_world_y_authorized",
        "terrain_runtime_authorized",
        "source_geometry_modified",
        "jouable_promotion_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")
    if hard.get("owner_rigid_translation_only") is not True:
        raise RuntimeError("owner_rigid_translation_only must be true")
    if hard.get("artifact_only") is not True:
        raise RuntimeError("artifact_only must be true")
    policy = contract["policy"]
    if policy.get("source_vertex_warping_allowed") is not False:
        raise RuntimeError("source vertex warping must remain forbidden")
    if policy.get("authorization_threshold") is not None:
        raise RuntimeError("locked measurement must not authorize runtime")


def evaluate_q(
    owner_residuals: dict[str, list[float]], q: float, deadband: float
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    all_post: list[float] = []
    shifts: list[float] = []
    owner_max_abs: list[float] = []
    owner_rows: list[dict[str, Any]] = []

    for building_id in sorted(owner_residuals, key=int):
        residuals = owner_residuals[building_id]
        shift = percentile([-value for value in residuals], q)
        post = [value + shift for value in residuals]
        abs_post = [abs(value) for value in post]
        max_abs = max(abs_post)
        shifts.append(shift)
        all_post.extend(post)
        owner_max_abs.append(max_abs)
        owner_rows.append(
            {
                "building_id": building_id,
                "sample_count": len(residuals),
                "rigid_shift_m": shift,
                "post_residual_median_m": statistics.median(post),
                "post_residual_min_m": min(post),
                "post_residual_max_m": max(post),
                "post_max_abs_residual_m": max_abs,
            }
        )

    abs_all = [abs(value) for value in all_post]
    summary = {
        "quantile": q,
        "owners": len(owner_residuals),
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
            "within_0_25m": sum(value <= 0.25 for value in abs_all),
            "within_0_50m": sum(value <= 0.50 for value in abs_all),
            "within_1m": sum(value <= 1.0 for value in abs_all),
            "positive_over_deadband": sum(value > deadband for value in all_post),
            "negative_below_deadband": sum(value < -deadband for value in all_post),
            "within_deadband": sum(abs(value) <= deadband for value in all_post),
        },
        "owner_max_abs_residual_m": {
            "p50": percentile(owner_max_abs, 0.50),
            "p90": percentile(owner_max_abs, 0.90),
            "p95": percentile(owner_max_abs, 0.95),
            "p99": percentile(owner_max_abs, 0.99),
            "max": max(owner_max_abs),
        },
    }
    return summary, owner_rows


def run(input_dir: Path, contract_path: Path, output_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    validate_contract(contract)
    expected = contract["expected_measurement"]

    residual_files = sorted(input_dir.rglob("residuals_*.csv"))
    evidence_files = sorted(input_dir.rglob("dtm_evidence_*.json"))
    if len(residual_files) != int(expected["dtm_tile_count"]):
        raise RuntimeError(f"residual shard count drift: {len(residual_files)}")
    if len(evidence_files) != int(expected["dtm_tile_count"]):
        raise RuntimeError(f"evidence shard count drift: {len(evidence_files)}")

    evidence = [json.loads(path.read_text(encoding="utf-8")) for path in evidence_files]
    tile_ids = sorted(str(row["tile"]) for row in evidence)
    if tile_ids != list(expected["dtm_tiles"]):
        raise RuntimeError("DTM tile set drift")
    for row in evidence:
        if row.get("runtime_authorized") is not False:
            raise RuntimeError(f"{row['tile']}: runtime authorization drift")
        if row.get("final_world_y_authorized") is not False:
            raise RuntimeError(f"{row['tile']}: final-world-Y authorization drift")

    owner_residuals: dict[str, list[float]] = defaultdict(list)
    seen_xyz: set[tuple[str, str, str, str]] = set()
    source_z_by_xy: dict[tuple[str, str, str], set[str]] = defaultdict(set)

    for path in residual_files:
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                building_id = str(row["building_id"])
                easting = str(row["easting"])
                northing = str(row["northing"])
                source_z = str(row["source_ground_z"])
                key_xyz = (building_id, easting, northing, source_z)
                if key_xyz in seen_xyz:
                    raise RuntimeError(f"duplicate official XYZ sample: {key_xyz}")
                seen_xyz.add(key_xyz)
                source_z_by_xy[(building_id, easting, northing)].add(source_z)
                owner_residuals[building_id].append(
                    float(row["residual_source_minus_dtm_m"])
                )

    sample_count = len(seen_xyz)
    multi_z_xy = sum(1 for values in source_z_by_xy.values() if len(values) > 1)
    if len(owner_residuals) != int(expected["owners"]):
        raise RuntimeError(f"owner count drift: {len(owner_residuals)}")
    if sample_count != int(expected["unique_ground_samples"]):
        raise RuntimeError(f"XYZ sample count drift: {sample_count}")
    if multi_z_xy != int(expected["same_xy_distinct_source_z_sample_count"]):
        raise RuntimeError(f"same-XY distinct-Z count drift: {multi_z_xy}")

    baseline_abs = [
        abs(value) for residuals in owner_residuals.values() for value in residuals
    ]
    baseline_p95 = percentile(baseline_abs, 0.95)

    policy = contract["policy"]
    deadband = float(policy["float_burial_deadband_m"])
    candidates: list[dict[str, Any]] = []
    rows_by_q: dict[float, list[dict[str, Any]]] = {}
    for raw_q in policy["candidate_quantiles"]:
        q = float(raw_q)
        summary, rows = evaluate_q(owner_residuals, q, deadband)
        candidates.append(summary)
        rows_by_q[q] = rows

    selected = min(
        candidates,
        key=lambda row: (
            float(row["post_residual_m"]["abs_p95"]),
            float(row["owner_max_abs_residual_m"]["p95"]),
            abs(float(row["quantile"]) - 0.5),
        ),
    )
    selected_q = float(selected["quantile"])
    selected_rows = rows_by_q[selected_q]

    def require_close(name: str, observed: float, wanted: float, tol: float = 1e-9) -> None:
        if not math.isclose(observed, wanted, rel_tol=0.0, abs_tol=tol):
            raise RuntimeError(f"{name} drift: expected {wanted}, got {observed}")

    require_close(
        "baseline p95",
        baseline_p95,
        float(expected["baseline_vertex_abs_p95_m"]),
    )
    require_close(
        "selected quantile",
        selected_q,
        float(expected["selected_quantile"]),
        tol=1e-12,
    )
    require_close(
        "post p95",
        float(selected["post_residual_m"]["abs_p95"]),
        float(expected["selected_post_abs_p95_m"]),
    )
    require_close(
        "median rigid shift",
        float(selected["shift_m"]["median"]),
        float(expected["selected_shift_median_m"]),
    )
    require_close(
        "owner max-abs p95",
        float(selected["owner_max_abs_residual_m"]["p95"]),
        float(expected["selected_owner_max_abs_p95_m"]),
    )
    if float(selected["post_residual_m"]["abs_p95"]) >= baseline_p95:
        raise RuntimeError("selected rigid-anchor policy does not improve baseline p95")

    output_dir.mkdir(parents=True, exist_ok=True)
    fields = [
        "building_id",
        "sample_count",
        "rigid_shift_m",
        "post_residual_median_m",
        "post_residual_min_m",
        "post_residual_max_m",
        "post_max_abs_residual_m",
    ]
    csv_path = output_dir / "rigid_anchor_selected_per_owner.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
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
    owner_path = output_dir / "rigid_anchor_selected_by_owner.json"
    owner_path.write_text(
        json.dumps(owner_map, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
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
    locks_path = output_dir / "dtm_tile_locks.json"
    locks_path.write_text(
        json.dumps(locks, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )

    report = {
        "schema": "grand-bruxelles-region-lod2-c01-dtm-rigid-anchor-locked-v1",
        "campaign_id": contract["campaign_id"],
        "production_base_sha": contract["production_base_sha"],
        "source_measurement_pr": 973,
        "source_shard_head_sha": contract["source_shards"]["head_sha"],
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
    report_path = output_dir / "dtm_rigid_anchor_locked.json"
    report_path.write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )

    output_hashes = {
        path.name: sha256_file(path)
        for path in [report_path, owner_path, csv_path, locks_path]
    }
    expected_hashes = contract.get("expected_output_sha256", {})
    if expected_hashes:
        for name, digest in output_hashes.items():
            if expected_hashes.get(name) != digest:
                raise RuntimeError(
                    f"output hash drift for {name}: expected {expected_hashes.get(name)}, got {digest}"
                )

    (output_dir / "result.sha256.json").write_text(
        json.dumps(output_hashes, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "C01_DTM_LOCKED_OK: "
        f"owners={len(owner_residuals)} samples={sample_count} "
        f"same_xy_distinct_z={multi_z_xy} q={selected_q:.2f} "
        f"baseline_p95={baseline_p95:.10f} "
        f"post_p95={selected['post_residual_m']['abs_p95']:.10f} "
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
        run(args.input_dir.resolve(), args.contract.resolve(), args.output_dir.resolve())
    except Exception as exc:
        print(f"C01_DTM_LOCK_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
