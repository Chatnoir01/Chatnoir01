#!/usr/bin/env python3
"""Compare one Ixelles cell's semantic UrbIS 3D heights against DSM-DTM candidates.

This is an evidence-only validator. It never approves runtime heights. Semantic evidence
must come from the current-main BuildingFaces matcher and DSM-DTM evidence may be read
from the historical specialist branch only after its exact Git blob is provenance-locked.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter, defaultdict
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
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    x = (len(values) - 1) * p
    lo, hi = math.floor(x), math.ceil(x)
    if lo == hi:
        return values[lo]
    return values[lo] * (hi - x) + values[hi] * (x - lo)


def finite_float(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def load_dsm_rows(path: Path, cell: str) -> dict[str, dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row.get("cell_id") != cell:
                continue
            building_id = row.get("building_id")
            if not building_id:
                continue
            current = by_id.get(building_id)
            rank = {"high": 2, "medium": 1, "insufficient": 0}.get(row.get("confidence", ""), -1)
            if current is None or rank > current["_rank"]:
                copy = dict(row)
                copy["_rank"] = rank
                by_id[building_id] = copy
    return by_id


def compare(semantic_payload: dict[str, Any], dsm_rows: dict[str, dict[str, Any]], cell: str = CELL) -> dict[str, Any]:
    if semantic_payload.get("cell") != cell:
        raise ValueError(f"semantic evidence cell mismatch: {semantic_payload.get('cell')!r}")
    semantic_policy = semantic_payload.get("policy") or {}
    if semantic_policy.get("crs") != "EPSG:31370":
        raise ValueError("semantic evidence must be EPSG:31370")
    if semantic_policy.get("runtime_approval") is not False:
        raise ValueError("semantic input must remain evidence-only")

    records: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    for match in semantic_payload.get("matches", []):
        if match.get("status") != "matched_semantic_evidence":
            continue
        building_id = match.get("matched_inspire_id")
        semantic_h = finite_float(match.get("semantic_height_m"))
        if not building_id or semantic_h is None:
            status_counts["semantic_invalid"] += 1
            continue
        dsm = dsm_rows.get(str(building_id))
        if dsm is None:
            status_counts["dsm_missing"] += 1
            continue
        confidence = dsm.get("confidence", "")
        p50 = finite_float(dsm.get("height_p50_m"))
        p75 = finite_float(dsm.get("height_p75_m"))
        p90 = finite_float(dsm.get("height_p90_m"))
        if confidence not in ("high", "medium") or p50 is None or p75 is None or p90 is None:
            status_counts["dsm_insufficient"] += 1
            continue
        candidate = p75 if confidence == "high" else p50
        delta = candidate - semantic_h
        abs_delta = abs(delta)
        if abs_delta <= STRONG_DELTA_M:
            agreement = "strong"
        elif abs_delta <= MODERATE_DELTA_M:
            agreement = "moderate"
        else:
            agreement = "conflict"
        strong_validation_candidate = bool(
            agreement == "strong"
            and confidence == "high"
            and finite_float(match.get("match_score")) is not None
            and float(match["match_score"]) >= MIN_STRONG_MATCH_SCORE
            and finite_float(match.get("match_margin")) is not None
            and float(match["match_margin"]) >= MIN_STRONG_MATCH_MARGIN
        )
        status_counts[agreement] += 1
        records.append({
            "building_id": str(building_id),
            "busolid_id": str(match.get("busolid_id")),
            "semantic_height_m": semantic_h,
            "semantic_match_score": finite_float(match.get("match_score")),
            "semantic_match_margin": finite_float(match.get("match_margin")),
            "dsm_confidence": confidence,
            "dsm_height_p50_m": p50,
            "dsm_height_p75_m": p75,
            "dsm_height_p90_m": p90,
            "dsm_policy_candidate_m": candidate,
            "candidate_minus_semantic_m": delta,
            "abs_delta_m": abs_delta,
            "agreement": agreement,
            "strong_validation_candidate": strong_validation_candidate,
            "runtime_approved": False,
        })

    abs_deltas = [r["abs_delta_m"] for r in records]
    signed_deltas = [r["candidate_minus_semantic_m"] for r in records]
    n = len(records)
    def fraction(limit: float) -> float | None:
        return None if not n else sum(v <= limit for v in abs_deltas) / n

    return {
        "schema": SCHEMA,
        "cell": cell,
        "bbox_epsg31370": [149000.0, 169000.0, 149500.0, 169500.0],
        "source_crs": "EPSG:31370",
        "policy": {
            "semantic_height": "median ROOFSURFACE Z minus median GROUNDSURFACE Z",
            "dsm_candidate": "p75 when DSM-DTM confidence=high; p50 when medium",
            "agreement_thresholds_m": {"strong_max": STRONG_DELTA_M, "moderate_max": MODERATE_DELTA_M, "severe_outlier_gt": SEVERE_DELTA_M},
            "strong_validation_min_semantic_match_score": MIN_STRONG_MATCH_SCORE,
            "strong_validation_min_semantic_match_margin": MIN_STRONG_MATCH_MARGIN,
            "runtime_approval": False,
            "note": "strong_validation_candidate is evidence priority only; it is not runtime approval",
        },
        "counts": {
            "semantic_matched_inputs": sum(1 for m in semantic_payload.get("matches", []) if m.get("status") == "matched_semantic_evidence"),
            "joined_comparisons": n,
            **dict(sorted(status_counts.items())),
            "strong_validation_candidates": sum(r["strong_validation_candidate"] for r in records),
            "outliers_gt_8m": sum(r["abs_delta_m"] > SEVERE_DELTA_M for r in records),
        },
        "delta_summary_m": {
            "signed_mean": statistics.fmean(signed_deltas) if signed_deltas else None,
            "signed_median": statistics.median(signed_deltas) if signed_deltas else None,
            "abs_median": statistics.median(abs_deltas) if abs_deltas else None,
            "abs_p75": percentile(abs_deltas, 0.75),
            "abs_p90": percentile(abs_deltas, 0.90),
            "abs_p95": percentile(abs_deltas, 0.95),
            "within_1m_fraction": fraction(1.0),
            "within_2m_fraction": fraction(2.0),
            "within_4m_fraction": fraction(4.0),
            "within_8m_fraction": fraction(8.0),
        },
        "records": sorted(records, key=lambda r: (r["abs_delta_m"], r["building_id"]), reverse=True),
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
