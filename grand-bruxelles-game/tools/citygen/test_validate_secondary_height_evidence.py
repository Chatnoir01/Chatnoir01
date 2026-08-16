#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "validate_secondary_height_evidence", HERE / "validate_secondary_height_evidence.py"
)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

REVIEW = {
    "format": "grand-bruxelles-citygen-manual-frontier-review-v1",
    "cell_id": "bxl-e149000-n169000-s500",
    "crs": "EPSG:31370",
    "manual_frontier_ready": True,
    "height_review": {
        "candidate_count": 2,
        "flagged_candidate_count": 0,
        "flagged_building_ids": [],
        "candidates": [
            {"building_id": "building-a", "candidate_height_m": 18.2, "confidence": "high", "review_flags": []},
            {"building_id": "building-b", "candidate_height_m": 11.4, "confidence": "medium", "review_flags": []},
        ],
        "independent_secondary_validation_required": True,
        "source_candidate_digest": "height-digest",
    },
    "terrain_review": {
        "selected_resolution_m": 2.0,
        "selected_p95_abs_error_m": 0.12,
        "remaining_runtime_gates": ["seams", "normals", "collisions", "streaming", "performance", "photo_match"],
        "source_evidence_digest": "terrain-digest",
    },
    "blockers": ["secondary_independent_height_validation_missing", "terrain_runtime_validation_missing"],
    "runtime_promotion_allowed": False,
    "status": "manual_review_ready_runtime_forbidden",
    "next_actions": {
        "heights": "cross_check_candidates_against_independent_authoritative_height_source",
        "terrain": "run_seams_normals_collisions_streaming_performance_photo_match_gates",
    },
    "review_digest": "review-digest",
}

SECONDARY = {
    "schema": "grand-bruxelles-ixelles-semantic-dsm-comparison-v1",
    "cell": REVIEW["cell_id"],
    "source_crs": "EPSG:31370",
    "policy": {"runtime_approval": False},
    "records": [
        {
            "building_id": "building-a",
            "semantic_height_m": 17.4,
            "semantic_match_score": 0.97,
            "semantic_match_margin": 0.42,
            "dsm_confidence": "high",
            "dsm_policy_candidate_m": 18.2,
            "abs_delta_m": 0.8,
            "agreement": "strong",
            "strong_validation_candidate": True,
            "runtime_approved": False,
        },
        {
            "building_id": "building-b",
            "semantic_height_m": 15.9,
            "semantic_match_score": 0.95,
            "semantic_match_margin": 0.33,
            "dsm_confidence": "medium",
            "dsm_policy_candidate_m": 11.4,
            "abs_delta_m": 4.5,
            "agreement": "conflict",
            "strong_validation_candidate": False,
            "runtime_approved": False,
        },
    ],
    "runtime_approved": False,
}

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    review_path = root / "review.json"
    secondary_path = root / "secondary.json"
    review_path.write_text(json.dumps(REVIEW), encoding="utf-8")
    secondary_path.write_text(json.dumps(SECONDARY), encoding="utf-8")

    result = mod.validate(review_path, secondary_path)
    assert result["cell_id"] == REVIEW["cell_id"]
    assert result["runtime_promotion_allowed"] is False
    assert result["validated_candidate_count"] == 1
    assert result["blocked_candidate_count"] == 1
    assert result["secondary_validation_complete"] is False
    by_id = {row["building_id"]: row for row in result["candidates"]}
    assert by_id["building-a"]["secondary_status"] == "validated"
    assert by_id["building-a"]["runtime_approved"] is False
    assert by_id["building-b"]["secondary_status"] == "blocked_conflict"
    assert "secondary_independent_height_validation_incomplete" in result["blockers"]
    assert "terrain_runtime_validation_missing" in result["blockers"]

    mismatch = dict(SECONDARY)
    mismatch["cell"] = "bxl-e149500-n169000-s500"
    secondary_path.write_text(json.dumps(mismatch), encoding="utf-8")
    try:
        mod.validate(review_path, secondary_path)
    except ValueError as exc:
        assert "cell identity mismatch" in str(exc)
    else:
        raise AssertionError("cross-cell secondary evidence was accepted")

    unsafe = dict(SECONDARY)
    unsafe["runtime_approved"] = True
    secondary_path.write_text(json.dumps(unsafe), encoding="utf-8")
    try:
        mod.validate(review_path, secondary_path)
    except ValueError as exc:
        assert "runtime-unapproved" in str(exc)
    else:
        raise AssertionError("runtime-approved secondary evidence was accepted")

print("CITYGEN_SECONDARY_HEIGHT_VALIDATION_OK validated=1 blocked=1 runtime_promotion=false")
