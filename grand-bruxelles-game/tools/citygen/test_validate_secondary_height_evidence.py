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

CELL = "bxl-e149000-n169000-s500"
AUTO = {
    "format": "grand-bruxelles-cell-building-height-candidates-v1",
    "cell_id": CELL,
    "crs": "EPSG:31370",
    "candidate_count": 2,
    "runtime_promotion_allowed": False,
    "candidate_digest": "height-digest",
    "blockers": ["secondary_independent_height_validation_missing", "terrain_runtime_validation_missing"],
    "buildings": [
        {"building_id": "building-a", "candidate_height_m": 18.2, "confidence": "high", "runtime_approved": False},
        {"building_id": "building-b", "candidate_height_m": 11.4, "confidence": "medium", "runtime_approved": False},
    ],
}
SECONDARY = {
    "schema": "grand-bruxelles-ixelles-semantic-dsm-comparison-v1",
    "cell": CELL,
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
    candidates_path = root / "height-candidates.json"
    secondary_path = root / "secondary.json"
    candidates_path.write_text(json.dumps(AUTO), encoding="utf-8")
    secondary_path.write_text(json.dumps(SECONDARY), encoding="utf-8")

    result = mod.validate(candidates_path, secondary_path)
    assert result["cell_id"] == CELL
    assert result["height_candidate_source_kind"] == "autonomous_measured_height_candidates"
    assert result["source_candidate_digest"] == "height-digest"
    assert result["source_review_digest"] is None
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
        mod.validate(candidates_path, secondary_path)
    except ValueError as exc:
        assert "cell identity mismatch" in str(exc)
    else:
        raise AssertionError("cross-cell secondary evidence was accepted")

    unsafe = dict(AUTO)
    unsafe["runtime_promotion_allowed"] = True
    candidates_path.write_text(json.dumps(unsafe), encoding="utf-8")
    secondary_path.write_text(json.dumps(SECONDARY), encoding="utf-8")
    try:
        mod.validate(candidates_path, secondary_path)
    except ValueError as exc:
        assert "forbid runtime promotion" in str(exc)
    else:
        raise AssertionError("unsafe autonomous candidate source was accepted")

    complete_source = dict(AUTO)
    complete_source["candidate_count"] = 1
    complete_source["buildings"] = [AUTO["buildings"][0]]
    candidates_path.write_text(json.dumps(complete_source), encoding="utf-8")
    complete_secondary = dict(SECONDARY)
    complete_secondary["records"] = [SECONDARY["records"][0]]
    secondary_path.write_text(json.dumps(complete_secondary), encoding="utf-8")
    complete = mod.validate(candidates_path, secondary_path)
    assert complete["secondary_validation_complete"] is True
    assert complete["blocked_candidate_count"] == 0
    assert complete["next_action"] == "run_remaining_terrain_runtime_gates_then_promotion_readiness"
    assert complete["runtime_promotion_allowed"] is False

print("CITYGEN_SECONDARY_HEIGHT_VALIDATION_OK source=automatic validated=1 blocked=1 complete_path=true runtime_promotion=false")
