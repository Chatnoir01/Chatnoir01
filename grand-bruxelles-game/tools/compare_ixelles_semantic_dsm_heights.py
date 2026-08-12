#!/usr/bin/env python3
"""Compare one Ixelles cell's semantic UrbIS 3D heights against DSM-DTM candidates.

Evidence-only validator. It never approves runtime heights.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
CELL = "bxl-e149000-n169000-s500"
STRONG_DELTA_M = 2.0
MODERATE_DELTA_M = 4.0
SEVERE_DELTA_M = 8.0
MIN_STRONG_MATCH_SCORE = 0.90
MIN_STRONG_MATCH_MARGIN = 0.25


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    pos = (len(ordered) - 1) * p
    lo, hi = math.floor(pos), math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def finite_float(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def load_dsm_rows(path: Path, cell: str) -> dict[str, dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    rank_map = {"high": 2, "medium": 1, "insufficient": 0}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row.get("cell_id") != cell:
                continue
            building_id = row.get("building_id")
            if not building_id:
                continue
            rank = rank_map.get(row.get("confidence", ""), -1)
            current = by_id.get(building_id)
            if current is None or rank > current["_rank"]:
                copy = dict(row)
                copy["_rank"] = rank
                by_id[building_id] = copy
    return by_id


def compare(semantic_payload: dict[str, Any], dsm_rows: dict[str, dict[str, Any]], cell: str = CELL) -> dict[str, Any]:
    if semantic_payload.get("cell") != cell:
        raise ValueError("semantic evidence cell mismatch")
    policy = semantic_payload.get("policy") or {}
    if policy.get("crs") != "EPSG:31370":
        raise ValueError("semantic evidence must be EPSG:31370")
    if policy.get("runtime_approval") is not False:
        raise ValueError("semantic evidence must remain runtime-unapproved")

    records: list[dict[str, Any]] = []
    statuses: Counter[str] = Counter()
    semantic_inputs = [m for m in semantic_payload.get("matches", []) if m.get("status") == "matched_semantic_evidence"]
    for match in semantic_inputs:
        building_id = str(match.get("matched_inspire_id") or "")
        semantic_h = finite_float(match.get("semantic_height_m"))
        if not building_id or semantic_h is None:
            statuses["semantic_invalid"] += 1
            continue
        dsm = dsm_rows.get(building_id)
        if dsm is None:
            statuses["dsm_missing"] += 1
            continue
        confidence = dsm.get("confidence", "")
        p50, p75, p90 = (finite_float(dsm.get(key)) for key in ("height_p50_m", "height_p75_m", "height_p90_m"))
        if confidence not in ("high", "medium") or None in (p50, p75, p90):
            statuses["dsm_insufficient"] += 1
            continue
        assert p50 is not None and p75 is not None and p90 is not None
        candidate = p75 if confidence == "high" else p50
        delta = candidate - semantic_h
        abs_delta = abs(delta)
        agreement = "strong" if abs_delta <= STRONG_DELTA_M else "moderate" if abs_delta <= MODERATE_DELTA_M else "conflict"
        score = finite_float(match.get("match_score"))
        margin = finite_float(match.get("match_margin"))
        validation_candidate = bool(agreement == "strong" and confidence == "high" and score is not None and score >= MIN_STRONG_MATCH_SCORE and margin is not None and margin >= MIN_STRONG_MATCH_MARGIN)
        statuses[agreement] += 1
        records.append({
            "building_id": building_id,
            "busolid_id": str(match.get("busolid_id") or ""),
            "semantic_height_m": semantic_h,
            "semantic_match_score": score,
            "semantic_match_margin": margin,
            "dsm_confidence": confidence,
            "dsm_height_p50_m": p50,
            "dsm_height_p75_m": p75,
            "dsm_height_p90_m": p90,
            "dsm_policy_candidate_m": candidate,
            "candidate_minus_semantic_m": delta,
            "abs_delta_m": abs_delta,
            "agreement": agreement,
            "strong_validation_candidate": validation_candidate,
            "runtime_approved": False,
        })

    abs_deltas = [r["abs_delta_m"] for r in records]
    signed = [r["candidate_minus_semantic_m"] for r in records]
    n = len(records)
    frac = lambda limit: None if not n else sum(v <= limit for v in abs_deltas) / n
    return {
        "schema": SCHEMA,
        "cell": cell,
        "bbox_epsg31370": [149000.0, 169000.0, 149500.0, 169500.0],
        "source_crs": "EPSG:31370",
        "policy": {
            "semantic_height": "median ROOFSURFACE Z minus median GROUNDSURFACE Z",
            "dsm_candidate": "p75 when confidence=high; p50 when confidence=medium",
            "agreement_thresholds_m": {"strong_max": 2.0, "moderate_max": 4.0, "severe_outlier_gt": 8.0},
            "strong_validation_min_semantic_match_score": 0.90,
            "strong_validation_min_semantic_match_margin": 0.25,
            "runtime_approval": False,
            "note": "strong_validation_candidate is evidence priority only, never runtime approval",
        },
        "counts": {
            "semantic_matched_inputs": len(semantic_inputs),
            "joined_comparisons": n,
            **dict(sorted(statuses.items())),
            "strong_validation_candidates": sum(r["strong_validation_candidate"] for r in records),
            "outliers_gt_8m": sum(r["abs_delta_m"] > SEVERE_DELTA_M for r in records),
        },
        "delta_summary_m": {
            "signed_mean": statistics.fmean(signed) if signed else None,
            "signed_median": statistics.median(signed) if signed else None,
            "abs_median": statistics.median(abs_deltas) if abs_deltas else None,
            "abs_p75": percentile(abs_deltas, 0.75),
            "abs_p90": percentile(abs_deltas, 0.90),
            "abs_p95": percentile(abs_deltas, 0.95),
            "within_1m_fraction": frac(1.0),
            "within_2m_fraction": frac(2.0),
            "within_4m_fraction": frac(4.0),
            "within_8m_fraction": frac(8.0),
        },
        "records": sorted(records, key=lambda r: (-r["abs_delta_m"], r["building_id"])),
        "runtime_approved": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--semantic", type=Path, required=True)
    parser.add_argument("--dsm-csv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cell", default=CELL)
    args = parser.parse_args()
    semantic = json.loads(args.semantic.read_text(encoding="utf-8"))
    result = compare(semantic, load_dsm_rows(args.dsm_csv, args.cell), args.cell)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"counts": result["counts"], "delta_summary_m": result["delta_summary_m"], "runtime_approved": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
