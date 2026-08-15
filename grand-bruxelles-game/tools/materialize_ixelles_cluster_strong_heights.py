#!/usr/bin/env python3
"""Materialize strong, source-cross-checked height contracts for streamed Ixelles cells.

Only official UrbIS 3D semantic heights that strongly agree with high-confidence
DSM-DTM evidence are exposed as visual runtime candidates. Conflicts remain absent
and every record stays runtime-unapproved.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import compare_ixelles_semantic_dsm_heights as comparison

SCHEMA = "grand-bruxelles-ixelles-strong-height-candidates-v1"
DEFAULT_DISTRIBUTION_SHA256 = "090f4a6aada5c7c19609860d7ee3956ce0f06379c991533975bcf1ddb848dfaa"
DEFAULT_GPKG_SHA256 = "2aa3057da9d0cfd656baf684fe53d343629b1539a648fbb69fff983327993c78"
DEFAULT_DSM_EVIDENCE_GIT_BLOB_SHA1 = "fe5df2040a0fb41f6374e90826a56472f38b1116"
DEFAULT_SOURCE_REVISION = "20260808"


def _finite(value: Any) -> float:
    out = comparison.finite_float(value)
    if out is None:
        raise ValueError(f"Expected finite numeric value, got {value!r}")
    return out


def _candidate_sort_key(record: dict[str, Any]) -> tuple[Any, ...]:
    # Multiple UrbIS BuildingSolids may legitimately overlap one 2D building.
    # Prefer the strongest semantic footprint match, then margin, then the
    # tightest cross-source height agreement, with a stable BUSOLID_ID tie-break.
    return (
        -_finite(record.get("semantic_match_score")),
        -_finite(record.get("semantic_match_margin")),
        _finite(record.get("abs_delta_m")),
        str(record.get("busolid_id") or ""),
    )


def materialize_contract(
    semantic_payload: dict[str, Any],
    dsm_rows: dict[str, dict[str, Any]],
    runtime_cell: dict[str, Any],
    *,
    cell_id: str,
    distribution_sha256: str = DEFAULT_DISTRIBUTION_SHA256,
    gpkg_sha256: str = DEFAULT_GPKG_SHA256,
    dsm_evidence_git_blob_sha1: str = DEFAULT_DSM_EVIDENCE_GIT_BLOB_SHA1,
    source_revision: str = DEFAULT_SOURCE_REVISION,
) -> dict[str, Any]:
    if runtime_cell.get("cell_id") != cell_id:
        raise ValueError("runtime cell id mismatch")
    bbox = runtime_cell.get("source_bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError("runtime cell source_bbox missing")
    coords = runtime_cell.get("coordinate_system") or {}
    if coords.get("coordinates_are_current_game_world") is not True:
        raise ValueError("runtime cell must use current game-world coordinates")
    accuracy = runtime_cell.get("accuracy") or {}
    if accuracy.get("plan_geometry") != "official_urbis":
        raise ValueError("runtime footprints must remain official UrbIS plan geometry")

    compared = comparison.compare(semantic_payload, dsm_rows, cell_id)
    runtime_ids = {
        str(building.get("id") or "")
        for building in runtime_cell.get("buildings", [])
        if building.get("id")
    }
    if not runtime_ids:
        raise ValueError("runtime cell has no building footprints")

    by_building: dict[str, list[dict[str, Any]]] = {}
    strong_before_runtime = 0
    strong_inside_runtime_records = 0
    for record in compared["records"]:
        if not record.get("strong_validation_candidate"):
            continue
        strong_before_runtime += 1
        building_id = str(record.get("building_id") or "")
        if building_id not in runtime_ids:
            continue
        strong_inside_runtime_records += 1
        if record.get("agreement") != "strong" or record.get("dsm_confidence") != "high":
            raise ValueError("strong validation invariant drifted")
        if record.get("runtime_approved") is not False:
            raise ValueError("comparison record unexpectedly runtime-approved")
        by_building.setdefault(building_id, []).append(record)

    selected: list[dict[str, Any]] = []
    duplicate_records_removed = 0
    for building_id in sorted(by_building):
        records = by_building[building_id]
        records.sort(key=_candidate_sort_key)
        chosen = records[0]
        duplicate_records_removed += len(records) - 1
        selected.append({
            "building_id": building_id,
            "busolid_id": str(chosen.get("busolid_id") or ""),
            "semantic_height_m": round(_finite(chosen["semantic_height_m"]), 6),
            "dsm_height_p50_m": round(_finite(chosen["dsm_height_p50_m"]), 6),
            "dsm_height_p75_m": round(_finite(chosen["dsm_height_p75_m"]), 6),
            "abs_delta_m": round(_finite(chosen["abs_delta_m"]), 6),
            "semantic_match_score": _finite(chosen["semantic_match_score"]),
            "semantic_match_margin": _finite(chosen["semantic_match_margin"]),
            "visual_runtime_eligible": True,
            "runtime_approved": False,
        })

    eligible_ids = {record["building_id"] for record in selected}
    if len(eligible_ids) != len(selected):
        raise ValueError("strong-height contract contains duplicate building ids")

    return {
        "schema": SCHEMA,
        "cell_id": cell_id,
        "bbox_epsg31370": [float(value) for value in bbox],
        "policy": {
            "origin_policy_pr": 103,
            "semantic_source": "UrbIS 3D ROOFSURFACE median Z - GROUNDSURFACE median Z",
            "secondary_source": "corrected DSM-DTM building evidence",
            "max_abs_delta_m": comparison.STRONG_DELTA_M,
            "required_dsm_confidence": "high",
            "min_semantic_match_score": comparison.MIN_STRONG_MATCH_SCORE,
            "min_semantic_match_margin": comparison.MIN_STRONG_MATCH_MARGIN,
            "urbis3d_distribution_sha256": distribution_sha256.lower(),
            "urbis3d_gpkg_sha256": gpkg_sha256.lower(),
            "urbis3d_source_revision": source_revision,
            "dsm_evidence_git_blob_sha1": dsm_evidence_git_blob_sha1.lower(),
        },
        "runtime_footprint_count": len(runtime_ids),
        "semantic_matched_inputs": int(compared["counts"].get("semantic_matched_inputs", 0)),
        "joined_comparisons": int(compared["counts"].get("joined_comparisons", 0)),
        "strong_candidates_before_runtime_intersection": strong_before_runtime,
        "strong_candidates_outside_runtime": strong_before_runtime - strong_inside_runtime_records,
        "duplicate_strong_records_removed": duplicate_records_removed,
        "eligible_count": len(selected),
        "records": selected,
        "runtime_approved": False,
        "purpose": "bounded deterministic visual-runtime candidate massing only; cross-source conflicts remain absent",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--semantic", type=Path, required=True)
    parser.add_argument("--dsm-csv", type=Path, required=True)
    parser.add_argument("--runtime-cell", type=Path, required=True)
    parser.add_argument("--cell-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--distribution-sha256", default=DEFAULT_DISTRIBUTION_SHA256)
    parser.add_argument("--gpkg-sha256", default=DEFAULT_GPKG_SHA256)
    parser.add_argument("--dsm-evidence-git-blob-sha1", default=DEFAULT_DSM_EVIDENCE_GIT_BLOB_SHA1)
    parser.add_argument("--source-revision", default=DEFAULT_SOURCE_REVISION)
    args = parser.parse_args()

    semantic = json.loads(args.semantic.read_text(encoding="utf-8"))
    runtime_cell = json.loads(args.runtime_cell.read_text(encoding="utf-8"))
    dsm_rows = comparison.load_dsm_rows(args.dsm_csv, args.cell_id)
    result = materialize_contract(
        semantic,
        dsm_rows,
        runtime_cell,
        cell_id=args.cell_id,
        distribution_sha256=args.distribution_sha256,
        gpkg_sha256=args.gpkg_sha256,
        dsm_evidence_git_blob_sha1=args.dsm_evidence_git_blob_sha1,
        source_revision=args.source_revision,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({
        "cell_id": result["cell_id"],
        "runtime_footprints": result["runtime_footprint_count"],
        "joined": result["joined_comparisons"],
        "strong_before_runtime": result["strong_candidates_before_runtime_intersection"],
        "eligible_count": result["eligible_count"],
        "duplicates_removed": result["duplicate_strong_records_removed"],
        "runtime_approved": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())