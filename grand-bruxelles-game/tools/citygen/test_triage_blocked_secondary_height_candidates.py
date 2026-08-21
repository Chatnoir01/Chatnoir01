#!/usr/bin/env python3
"""Regression for fail-closed blocked secondary-height triage."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("triage_blocked_secondary_height_candidates.py")
spec = importlib.util.spec_from_file_location("blocked_height_triage", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

CELL = "bxl-e142000-n167000-s500"


def row(building_id: str, status: str, confidence: str, delta: float | None) -> dict:
    return {
        "building_id": building_id,
        "candidate_height_m": 10.0,
        "confidence": confidence,
        "secondary_status": status,
        "secondary_reason": "synthetic",
        "semantic_height_m": None if delta is None else 10.0 + delta,
        "abs_delta_m": delta,
        "semantic_match_score": None if delta is None else 0.99,
        "semantic_match_margin": None if delta is None else 0.8,
        "runtime_approved": False,
    }


validation = {
    "format": "grand-bruxelles-citygen-secondary-height-validation-v1",
    "cell_id": CELL,
    "crs": "EPSG:31370",
    "candidate_count": 7,
    "validated_candidate_count": 1,
    "blocked_candidate_count": 6,
    "runtime_promotion_allowed": False,
    "runtime_approved_count": 0,
    "candidates": [
        row("validated", "validated", "high", 0.4),
        row("missing", "blocked_missing_secondary_evidence", "high", None),
        row("mismatch", "blocked_candidate_mismatch", "high", 0.2),
        row("conflict", "blocked_conflict", "high", 7.0),
        row("strong-medium", "blocked_insufficient_secondary_confidence", "medium", 1.0),
        row("moderate-high", "blocked_insufficient_secondary_confidence", "high", 3.0),
        row("moderate-medium", "blocked_insufficient_secondary_confidence", "medium", 3.0),
    ],
}

secondary = {
    "schema": "grand-bruxelles-ixelles-semantic-dsm-comparison-v1",
    "cell": CELL,
    "source_crs": "EPSG:31370",
    "runtime_approved": False,
    "policy": {"runtime_approval": False},
    "records": [
        {"building_id": "validated", "agreement": "strong", "dsm_confidence": "high", "strong_validation_candidate": True, "runtime_approved": False},
        {"building_id": "mismatch", "agreement": "strong", "dsm_confidence": "high", "strong_validation_candidate": False, "runtime_approved": False},
        {"building_id": "conflict", "agreement": "conflict", "dsm_confidence": "high", "strong_validation_candidate": False, "runtime_approved": False},
        {"building_id": "strong-medium", "agreement": "strong", "dsm_confidence": "medium", "strong_validation_candidate": False, "runtime_approved": False},
        {"building_id": "moderate-high", "agreement": "moderate", "dsm_confidence": "high", "strong_validation_candidate": False, "runtime_approved": False},
        {"building_id": "moderate-medium", "agreement": "moderate", "dsm_confidence": "medium", "strong_validation_candidate": False, "runtime_approved": False},
    ],
}

result = module.triage(validation, secondary)
assert result["schema"] == "grand-bruxelles-citygen-blocked-secondary-height-triage-v1"
assert result["cell_id"] == CELL
assert result["counts"]["validated_ignored"] == 1
assert result["counts"]["blocked_total"] == 6
assert result["counts"]["secondary_coverage_gap"] == 1
assert result["counts"]["candidate_provenance_mismatch"] == 1
assert result["counts"]["independent_height_adjudication_required"] == 1
assert result["counts"]["primary_confidence_corroboration_required"] == 1
assert result["counts"]["cross_source_height_adjudication_required"] == 1
assert result["counts"]["dual_uncertainty_requires_new_evidence"] == 1
assert result["counts"]["adjudication_frontier"] == 4
assert result["policy"]["read_only"] is True
assert result["policy"]["thresholds_changed"] is False
assert result["policy"]["runtime_approval"] is False
assert result["runtime_promotion_allowed"] is False
assert all(item["runtime_approved"] is False for item in result["blocked_candidates"])
assert all(item["automatic_resolution_allowed"] is False for item in result["blocked_candidates"])

routes = {item["building_id"]: item["triage_route"] for item in result["blocked_candidates"]}
assert routes["missing"] == "secondary_coverage_gap"
assert routes["mismatch"] == "candidate_provenance_mismatch"
assert routes["conflict"] == "independent_height_adjudication_required"
assert routes["strong-medium"] == "primary_confidence_corroboration_required"
assert routes["moderate-high"] == "cross_source_height_adjudication_required"
assert routes["moderate-medium"] == "dual_uncertainty_requires_new_evidence"

print("BLOCKED_SECONDARY_HEIGHT_TRIAGE_TEST_OK blocked=6 adjudication=4 runtime_promotion=false thresholds_changed=false")
