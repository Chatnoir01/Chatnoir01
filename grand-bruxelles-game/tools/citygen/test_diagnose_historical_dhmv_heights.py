#!/usr/bin/env python3
"""Regression for read-only historical DHMV third-height diagnostics."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("diagnose_historical_dhmv_heights.py")
spec = importlib.util.spec_from_file_location("historical_dhmv", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

CELL = "bxl-e142000-n167000-s500"

triage = {
    "schema": "grand-bruxelles-citygen-blocked-secondary-height-triage-v1",
    "cell_id": CELL,
    "crs": "EPSG:31370",
    "runtime_promotion_allowed": False,
    "policy": {"read_only": True, "thresholds_changed": False, "runtime_approval": False},
    "blocked_candidates": [
        {"building_id": "both", "triage_route": "primary_confidence_corroboration_required", "runtime_approved": False, "automatic_resolution_allowed": False},
        {"building_id": "primary-only", "triage_route": "cross_source_height_adjudication_required", "runtime_approved": False, "automatic_resolution_allowed": False},
        {"building_id": "semantic-only", "triage_route": "cross_source_height_adjudication_required", "runtime_approved": False, "automatic_resolution_allowed": False},
        {"building_id": "conflict", "triage_route": "independent_height_adjudication_required", "runtime_approved": False, "automatic_resolution_allowed": False},
        {"building_id": "insufficient", "triage_route": "dual_uncertainty_requires_new_evidence", "runtime_approved": False, "automatic_resolution_allowed": False},
        {"building_id": "coverage-gap", "triage_route": "secondary_coverage_gap", "runtime_approved": False, "automatic_resolution_allowed": False},
    ],
}
primary = {
    "format": "grand-bruxelles-cell-building-height-candidates-v1",
    "cell_id": CELL,
    "crs": "EPSG:31370",
    "runtime_promotion_allowed": False,
    "runtime_approved_count": 0,
    "buildings": [
        {"building_id": key, "candidate_height_m": 10.0, "confidence": "high", "runtime_approved": False}
        for key in ("both", "primary-only", "semantic-only", "conflict", "insufficient", "coverage-gap")
    ],
}
secondary = {
    "schema": "grand-bruxelles-ixelles-semantic-dsm-comparison-v1",
    "cell": CELL,
    "source_crs": "EPSG:31370",
    "runtime_approved": False,
    "policy": {"runtime_approval": False},
    "records": [
        {"building_id": "both", "semantic_height_m": 10.5, "runtime_approved": False},
        {"building_id": "primary-only", "semantic_height_m": 14.0, "runtime_approved": False},
        {"building_id": "semantic-only", "semantic_height_m": 14.0, "runtime_approved": False},
        {"building_id": "conflict", "semantic_height_m": 14.0, "runtime_approved": False},
        {"building_id": "insufficient", "semantic_height_m": 12.0, "runtime_approved": False},
    ],
}
measurements = {
    "both": {"candidate_height_m": 10.4, "confidence": "high", "height_stats": {}},
    "primary-only": {"candidate_height_m": 10.4, "confidence": "high", "height_stats": {}},
    "semantic-only": {"candidate_height_m": 13.7, "confidence": "high", "height_stats": {}},
    "conflict": {"candidate_height_m": 20.0, "confidence": "high", "height_stats": {}},
    "insufficient": {"candidate_height_m": None, "confidence": "insufficient", "height_stats": {}},
}
source = {
    "provider": "Digitaal Vlaanderen",
    "campaign": "DHMV II",
    "acquisition_start": "2013-02-20",
    "acquisition_end": "2015-04-20",
    "dsm_coverage_id": "DHMVII_DSM_1m",
    "dtm_coverage_id": "DHMVII_DTM_1m",
    "resolution_m": 1.0,
    "independence_basis": "separate provider and LiDAR acquisition campaign; historical only",
}

result = module.build_report(triage, primary, secondary, measurements, source)
assert result["schema"] == "grand-bruxelles-citygen-historical-dhmv-third-height-diagnostic-v1"
assert result["cell_id"] == CELL
assert result["counts"]["adjudication_candidates"] == 5
assert result["counts"]["coverage_gap_excluded"] == 1
assert result["counts"]["historical_corroborates_both"] == 1
assert result["counts"]["historical_corroborates_primary_only"] == 1
assert result["counts"]["historical_corroborates_semantic_only"] == 1
assert result["counts"]["historical_conflicts_both"] == 1
assert result["counts"]["historical_measurement_insufficient"] == 1
assert result["policy"]["read_only"] is True
assert result["policy"]["historical_evidence_is_runtime_authority"] is False
assert result["policy"]["automatic_resolution"] is False
assert result["policy"]["thresholds_changed"] is False
assert result["runtime_promotion_allowed"] is False
assert result["runtime_approved_count"] == 0
assert all(row["automatic_resolution_allowed"] is False for row in result["records"])
assert all(row["runtime_approved"] is False for row in result["records"])
assert result["policy"]["comparison_strong_delta_m"] == 2.0

by_id = {row["building_id"]: row for row in result["records"]}
assert by_id["both"]["historical_relation"] == "historical_corroborates_both"
assert by_id["primary-only"]["historical_relation"] == "historical_corroborates_primary_only"
assert by_id["semantic-only"]["historical_relation"] == "historical_corroborates_semantic_only"
assert by_id["conflict"]["historical_relation"] == "historical_conflicts_both"
assert by_id["insufficient"]["historical_relation"] == "historical_measurement_insufficient"

print("HISTORICAL_DHMV_HEIGHT_DIAGNOSTIC_TEST_OK candidates=5 runtime_promotion=false automatic_resolution=false")
