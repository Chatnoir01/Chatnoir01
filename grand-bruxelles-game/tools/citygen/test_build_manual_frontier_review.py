#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("build_manual_frontier_review", HERE / "build_manual_frontier_review.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

HEIGHTS = {
    "format": "grand-bruxelles-cell-building-height-candidates-v1",
    "cell_id": "bxl-e149000-n169000-s500",
    "crs": "EPSG:31370",
    "candidate_count": 2,
    "runtime_approved_count": 0,
    "runtime_promotion_allowed": False,
    "buildings": [
        {
            "building_id": "building-a",
            "candidate_height_m": 18.2,
            "confidence": "high",
            "runtime_approved": False,
            "secondary_validation_required": True,
            "height_stats": {"review_flags": []},
        },
        {
            "building_id": "building-b",
            "candidate_height_m": 11.4,
            "confidence": "medium",
            "runtime_approved": False,
            "secondary_validation_required": True,
            "height_stats": {"review_flags": ["large_p50_p90_spread_requires_secondary_review"]},
        },
    ],
    "candidate_digest": "height-digest",
}

TERRAIN = {
    "format": "grand-bruxelles-cell-dtm-lod-evidence-v1",
    "cell_id": "bxl-e149000-n169000-s500",
    "crs": "EPSG:31370",
    "runtime_approved": False,
    "selection": {
        "selected_resolution_m": 2.0,
        "selected_p95_abs_error_m": 0.12,
        "runtime_approved": False,
        "remaining_runtime_gates": ["seams", "normals", "collisions", "streaming", "performance", "photo_match"],
        "blockers": [],
    },
    "evidence_digest": "terrain-digest",
}

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    hp = root / "heights.json"
    tp = root / "terrain.json"
    hp.write_text(json.dumps(HEIGHTS), encoding="utf-8")
    tp.write_text(json.dumps(TERRAIN), encoding="utf-8")

    result = mod.build(hp, tp)
    assert result["cell_id"] == HEIGHTS["cell_id"]
    assert result["manual_frontier_ready"] is True
    assert result["runtime_promotion_allowed"] is False
    assert result["height_review"]["candidate_count"] == 2
    assert result["height_review"]["flagged_candidate_count"] == 1
    assert result["terrain_review"]["selected_resolution_m"] == 2.0
    assert result["terrain_review"]["remaining_runtime_gates"] == TERRAIN["selection"]["remaining_runtime_gates"]
    assert "secondary_independent_height_validation_missing" in result["blockers"]
    assert "terrain_runtime_validation_missing" in result["blockers"]

    bad = dict(HEIGHTS)
    bad["runtime_promotion_allowed"] = True
    hp.write_text(json.dumps(bad), encoding="utf-8")
    try:
        mod.build(hp, tp)
    except ValueError as exc:
        assert "forbid runtime promotion" in str(exc)
    else:
        raise AssertionError("unsafe height evidence was accepted")

    hp.write_text(json.dumps(HEIGHTS), encoding="utf-8")
    mismatch = dict(TERRAIN)
    mismatch["cell_id"] = "bxl-e149500-n169000-s500"
    tp.write_text(json.dumps(mismatch), encoding="utf-8")
    try:
        mod.build(hp, tp)
    except ValueError as exc:
        assert "cell identity mismatch" in str(exc)
    else:
        raise AssertionError("cross-cell evidence was accepted")

print("CITYGEN_MANUAL_FRONTIER_REVIEW_OK fail_closed=true runtime_promotion=false")
