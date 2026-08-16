#!/usr/bin/env python3
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "build_semantic_dsm_height_comparison",
    HERE / "build_semantic_dsm_height_comparison.py",
)
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

CELL = "bxl-e141500-n167500-s500"
REVIEW = {
    "format": "grand-bruxelles-citygen-manual-frontier-review-v1",
    "cell_id": CELL,
    "crs": "EPSG:31370",
    "runtime_promotion_allowed": False,
    "height_review": {
        "candidate_count": 3,
        "candidates": [
            {"building_id": "building-a", "candidate_height_m": 18.2, "confidence": "high"},
            {"building_id": "building-b", "candidate_height_m": 11.4, "confidence": "medium"},
            {"building_id": "building-c", "candidate_height_m": 8.0, "confidence": "high"},
        ],
    },
}
SEMANTIC = {
    "cell": CELL,
    "bbox_epsg31370": [141500.0, 167500.0, 142000.0, 168000.0],
    "policy": {"crs": "EPSG:31370", "runtime_approval": False},
    "matches": [
        {
            "matched_inspire_id": "building-a",
            "busolid_id": "solid-a",
            "status": "matched_semantic_evidence",
            "semantic_height_m": 17.4,
            "match_score": 0.97,
            "match_margin": 0.42,
            "runtime_approved": False,
        },
        {
            "matched_inspire_id": "building-b",
            "busolid_id": "solid-b",
            "status": "matched_semantic_evidence",
            "semantic_height_m": 15.9,
            "match_score": 0.95,
            "match_margin": 0.33,
            "runtime_approved": False,
        },
    ],
}

result = mod.build(SEMANTIC, REVIEW)
assert result["schema"] == "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
assert result["source_crs"] == "EPSG:31370"
assert result["runtime_approved"] is False
assert result["counts"]["manual_frontier_candidates"] == 3
assert result["counts"]["semantic_joined_records"] == 2
assert result["counts"]["strong_validation_candidates"] == 1
assert result["counts"]["conflicts"] == 1
assert result["counts"]["missing_secondary_records"] == 1
by_id = {row["building_id"]: row for row in result["records"]}
assert by_id["building-a"]["agreement"] == "strong"
assert by_id["building-a"]["strong_validation_candidate"] is True
assert by_id["building-b"]["agreement"] == "conflict"
assert by_id["building-b"]["strong_validation_candidate"] is False
assert all(row["runtime_approved"] is False for row in result["records"])

bad_cell = dict(SEMANTIC)
bad_cell["cell"] = "bxl-e149000-n169000-s500"
try:
    mod.build(bad_cell, REVIEW)
except ValueError as exc:
    assert "cell mismatch" in str(exc)
else:
    raise AssertionError("cross-cell semantic evidence was accepted")

unsafe = dict(SEMANTIC)
unsafe["policy"] = {"crs": "EPSG:31370", "runtime_approval": True}
try:
    mod.build(unsafe, REVIEW)
except ValueError as exc:
    assert "runtime-unapproved" in str(exc)
else:
    raise AssertionError("runtime-approved semantic evidence was accepted")

print("CITYGEN_REGIONAL_SECONDARY_EVIDENCE_TEST_OK joined=2 strong=1 missing=1 runtime_approved=false")
