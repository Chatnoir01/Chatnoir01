#!/usr/bin/env python3
"""Build conservative, auditable Ixelles runtime-height candidates.

This tool does NOT approve heights for runtime use. It converts validated DSM-DTM
per-building evidence into deterministic candidates that still require a secondary
source/visual validation gate before they may be baked into gameplay geometry.
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path

CONFIDENCE_RANK = {"insufficient": 0, "medium": 1, "high": 2}
MIN_HEIGHT_M = -0.5
MAX_HEIGHT_M = 250.0
COMPLEX_ROOF_SPREAD_M = 12.0


def parse_float(value: str | None) -> float | None:
    if value is None or value == "":
        return None
    return float(value)


def validate_quantiles(row: dict) -> tuple[float | None, float | None, float | None]:
    p50 = parse_float(row.get("height_p50_m"))
    p75 = parse_float(row.get("height_p75_m"))
    p90 = parse_float(row.get("height_p90_m"))
    values = [p50, p75, p90]
    if any(v is None for v in values):
        return p50, p75, p90
    assert p50 is not None and p75 is not None and p90 is not None
    if not (MIN_HEIGHT_M <= p50 <= p75 <= p90 <= MAX_HEIGHT_M):
        raise ValueError(
            f"Non-monotonic or implausible height quantiles for {row.get('building_id')}: "
            f"p50={p50}, p75={p75}, p90={p90}"
        )
    return p50, p75, p90


def evidence_key(row: dict) -> tuple:
    confidence = row.get("confidence", "")
    if confidence not in CONFIDENCE_RANK:
        raise ValueError(f"Unknown confidence {confidence!r}")
    plausible_fraction = parse_float(row.get("plausible_fraction_of_valid")) or 0.0
    plausible_pixels = int(row.get("pixel_count_plausible") or 0)
    valid_pixels = int(row.get("pixel_count_valid") or 0)
    # Deterministic preference: strongest confidence, then cleanest/largest evidence,
    # then stable cell id. Reverse sort is applied to numeric evidence only below.
    return (CONFIDENCE_RANK[confidence], plausible_fraction, plausible_pixels, valid_pixels)


def choose_membership(rows: list[dict]) -> dict:
    if not rows:
        raise ValueError("Cannot select from empty membership list")
    best_key = max(evidence_key(row) for row in rows)
    tied = [row for row in rows if evidence_key(row) == best_key]
    return sorted(tied, key=lambda r: (r.get("cell_id") or "", r.get("building_id") or ""))[0]


def candidate_from_row(row: dict) -> dict:
    confidence = row.get("confidence")
    p50, p75, p90 = validate_quantiles(row)
    terrain = parse_float(row.get("terrain_elevation_m_p50"))
    if terrain is None:
        raise ValueError(f"Missing terrain elevation for {row.get('building_id')}")

    selected = None
    percentile = None
    reason = "insufficient evidence; no candidate height emitted"
    if confidence == "high" and p75 is not None:
        selected = p75
        percentile = "p75"
        reason = "high-confidence DSM-DTM evidence; p75 limits ground/courtyard leakage while avoiding p90 roof/vegetation peaks"
    elif confidence == "medium" and p50 is not None:
        selected = p50
        percentile = "p50"
        reason = "medium-confidence evidence; conservative median only"

    spread = None if p50 is None or p90 is None else round(p90 - p50, 3)
    flags: list[str] = []
    if spread is not None and spread > COMPLEX_ROOF_SPREAD_M:
        flags.append("large_p50_p90_spread_requires_manual_or_secondary_review")
    if int(row.get("negative_below_noise_count") or 0) > 0:
        flags.append("negative_dsm_dtm_samples_present")
    if int(row.get("over_250m_count") or 0) > 0:
        flags.append("over_250m_samples_present")

    return {
        "building_id": row.get("building_id"),
        "source_cell_id": row.get("cell_id"),
        "terrain_elevation_m_p50": terrain,
        "evidence_confidence": confidence,
        "height_candidate_m": selected,
        "height_candidate_percentile": percentile,
        "p50_p90_spread_m": spread,
        "review_flags": flags,
        "selection_reason": reason,
        "requires_secondary_validation": selected is not None,
        "runtime_approved": False,
    }


def build_candidates(rows: list[dict]) -> dict:
    by_building: dict[str, list[dict]] = {}
    for row in rows:
        building_id = row.get("building_id")
        if not building_id:
            raise ValueError("Height evidence row missing building_id")
        validate_quantiles(row)
        by_building.setdefault(building_id, []).append(row)

    candidates = []
    duplicate_memberships = 0
    for building_id in sorted(by_building):
        memberships = by_building[building_id]
        duplicate_memberships += max(0, len(memberships) - 1)
        candidates.append(candidate_from_row(choose_membership(memberships)))

    counts = Counter(c["evidence_confidence"] for c in candidates)
    emitted = sum(c["height_candidate_m"] is not None for c in candidates)
    flagged = sum(bool(c["review_flags"]) for c in candidates)
    return {
        "schema": 1,
        "format": "grand-bruxelles-ixelles-runtime-height-candidates-v1",
        "source_crs": "EPSG:31370",
        "policy_status": "candidate_only_secondary_validation_required",
        "runtime_approved": False,
        "selection_policy": {
            "high": "p75 candidate",
            "medium": "p50 candidate",
            "insufficient": "no candidate",
            "deduplication": "highest confidence, plausible fraction, plausible pixel count, valid pixel count; stable cell id tie-break",
            "large_roof_spread_review_threshold_m": COMPLEX_ROOF_SPREAD_M,
        },
        "building_memberships_input": len(rows),
        "unique_buildings": len(candidates),
        "duplicate_memberships_removed": duplicate_memberships,
        "candidate_heights_emitted": emitted,
        "buildings_flagged_for_review": flagged,
        "confidence_counts": dict(sorted(counts.items())),
        "candidates": candidates,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with args.input_csv.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    result = build_candidates(rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "IXELLES_HEIGHT_CANDIDATES_VALID",
        result["unique_buildings"],
        result["candidate_heights_emitted"],
        result["buildings_flagged_for_review"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
