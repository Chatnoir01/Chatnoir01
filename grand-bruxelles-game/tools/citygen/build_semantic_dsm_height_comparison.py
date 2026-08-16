#!/usr/bin/env python3
"""Build fail-closed regional semantic-vs-DSM height evidence for CityGen.

Consumes a generic UrbIS3D semantic match payload plus a CityGen manual-frontier
review. It never approves runtime geometry or heights.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

# Kept compatible with the existing secondary validator while the producer itself
# is cell/municipality agnostic. The legacy schema name is an API compatibility
# label, not an Ixelles-specific execution constraint.
SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
CRS = "EPSG:31370"
REVIEW_FORMAT = "grand-bruxelles-citygen-manual-frontier-review-v1"
STRONG_DELTA_M = 2.0
MODERATE_DELTA_M = 4.0
MIN_STRONG_MATCH_SCORE = 0.90
MIN_STRONG_MATCH_MARGIN = 0.25


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _finite(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def build(semantic: dict[str, Any], review: dict[str, Any]) -> dict[str, Any]:
    if review.get("format") != REVIEW_FORMAT or review.get("crs") != CRS:
        raise ValueError("unsupported CityGen manual frontier review")
    if review.get("runtime_promotion_allowed") is not False:
        raise ValueError("manual frontier review must forbid runtime promotion")
    cell_id = str(review.get("cell_id") or "")
    if not cell_id or semantic.get("cell") != cell_id:
        raise ValueError("semantic evidence cell mismatch")
    policy = semantic.get("policy") or {}
    if policy.get("crs") != CRS or policy.get("runtime_approval") is not False:
        raise ValueError("semantic evidence must be EPSG:31370 and runtime-unapproved")

    candidate_rows = (review.get("height_review") or {}).get("candidates") or []
    if not isinstance(candidate_rows, list):
        raise ValueError("manual frontier height candidates are invalid")
    candidates: dict[str, dict[str, Any]] = {}
    for row in candidate_rows:
        if not isinstance(row, dict):
            raise ValueError("invalid manual frontier candidate row")
        building_id = str(row.get("building_id") or "")
        height = _finite(row.get("candidate_height_m"))
        if not building_id or height is None:
            raise ValueError("candidate is missing identity or finite height")
        if building_id in candidates:
            raise ValueError(f"duplicate candidate: {building_id}")
        candidates[building_id] = row

    semantic_by_id: dict[str, dict[str, Any]] = {}
    for match in semantic.get("matches") or []:
        if not isinstance(match, dict) or match.get("status") != "matched_semantic_evidence":
            continue
        building_id = str(match.get("matched_inspire_id") or "")
        if not building_id or building_id not in candidates:
            continue
        if match.get("runtime_approved") is not False:
            raise ValueError(f"semantic match must remain runtime-unapproved: {building_id}")
        if building_id in semantic_by_id:
            raise ValueError(f"duplicate semantic match: {building_id}")
        semantic_by_id[building_id] = match

    records: list[dict[str, Any]] = []
    for building_id, candidate in sorted(candidates.items()):
        match = semantic_by_id.get(building_id)
        if match is None:
            continue
        candidate_height = float(candidate["candidate_height_m"])
        semantic_height = _finite(match.get("semantic_height_m"))
        score = _finite(match.get("match_score"))
        margin = _finite(match.get("match_margin"))
        if semantic_height is None:
            continue
        abs_delta = abs(candidate_height - semantic_height)
        agreement = (
            "strong" if abs_delta <= STRONG_DELTA_M
            else "moderate" if abs_delta <= MODERATE_DELTA_M
            else "conflict"
        )
        confidence = str(candidate.get("confidence") or "")
        strong = bool(
            agreement == "strong"
            and confidence == "high"
            and score is not None
            and score >= MIN_STRONG_MATCH_SCORE
            and margin is not None
            and margin >= MIN_STRONG_MATCH_MARGIN
        )
        records.append({
            "building_id": building_id,
            "busolid_id": str(match.get("busolid_id") or ""),
            "semantic_height_m": semantic_height,
            "semantic_match_score": score,
            "semantic_match_margin": margin,
            "dsm_confidence": confidence,
            "dsm_policy_candidate_m": candidate_height,
            "abs_delta_m": abs_delta,
            "agreement": agreement,
            "strong_validation_candidate": strong,
            "runtime_approved": False,
        })

    return {
        "schema": SCHEMA,
        "cell": cell_id,
        "bbox_epsg31370": semantic.get("bbox_epsg31370"),
        "source_crs": CRS,
        "policy": {
            "semantic_height": "median ROOFSURFACE Z minus median GROUNDSURFACE Z",
            "dsm_candidate": "manual-frontier policy candidate",
            "agreement_thresholds_m": {
                "strong_max": STRONG_DELTA_M,
                "moderate_max": MODERATE_DELTA_M,
            },
            "strong_validation_min_semantic_match_score": MIN_STRONG_MATCH_SCORE,
            "strong_validation_min_semantic_match_margin": MIN_STRONG_MATCH_MARGIN,
            "runtime_approval": False,
            "note": "strong_validation_candidate is evidence only, never runtime approval",
        },
        "counts": {
            "manual_frontier_candidates": len(candidates),
            "semantic_joined_records": len(records),
            "strong_validation_candidates": sum(bool(r["strong_validation_candidate"]) for r in records),
            "conflicts": sum(r["agreement"] == "conflict" for r in records),
            "missing_secondary_records": len(candidates) - len(records),
        },
        "records": records,
        "runtime_approved": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--semantic", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(_read(args.semantic), _read(args.review))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CITYGEN_REGIONAL_SECONDARY_EVIDENCE_OK",
        result["cell"],
        f"joined={result['counts']['semantic_joined_records']}",
        f"strong={result['counts']['strong_validation_candidates']}",
        "runtime_approved=false",
    )


if __name__ == "__main__":
    main()
