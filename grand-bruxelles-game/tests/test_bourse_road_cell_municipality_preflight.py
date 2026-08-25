from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/qa/measure_bourse_road_cell_municipality_preflight.py"


def load_module():
    spec = importlib.util.spec_from_file_location("bourse_municipality_preflight", MODULE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def candidate_payload(module):
    rails = {key: False for key in module.CLOSED_RAILS}
    return {
        "schema": "grand-bruxelles-road-cell-coverage-candidates-v2",
        "status": "DISCOVERED_SOURCE_ONLY",
        "semantic_sha256": module.EXPECTED_CANDIDATE_SEMANTIC_SHA256,
        "road_source_sha256": module.EXPECTED_ROAD_SOURCE_SHA256,
        "road_semantic_sha256": module.EXPECTED_ROAD_SEMANTIC_SHA256,
        "candidate_cell_count": 8,
        **rails,
        "candidates": [
            {
                "grid_cell_id": module.TARGET_CELL_ID,
                "corridor_anchor_ids": [module.TARGET_ANCHOR_ID],
                "bbox": list(module.TARGET_BBOX),
                "road_count": module.TARGET_ROAD_COUNT,
                "road_ids": list(module.TARGET_ROAD_IDS),
                "point_hits": module.TARGET_POINT_HITS,
                "segment_hits": module.TARGET_SEGMENT_HITS,
                **rails,
            }
        ],
    }


def test_locked_bourse_candidate_is_accepted():
    module = load_module()
    row = module.validate_candidate_v2(candidate_payload(module))
    assert row["grid_cell_id"] == "E147500_N170000"
    assert row["road_ids"] == module.TARGET_ROAD_IDS


def test_candidate_self_authorization_is_rejected():
    module = load_module()
    payload = candidate_payload(module)
    payload["runtime_mount_authorized"] = True
    with pytest.raises(RuntimeError, match="runtime_mount_authorized"):
        module.validate_candidate_v2(payload)


def test_bourse_road_identity_drift_is_rejected():
    module = load_module()
    payload = candidate_payload(module)
    payload["candidates"][0]["road_ids"] = payload["candidates"][0]["road_ids"][:-1]
    with pytest.raises(RuntimeError, match="road IDs drift"):
        module.validate_candidate_v2(payload)


def test_semantic_basis_excludes_transport_and_git_base_only():
    module = load_module()
    result = {
        "production_base_sha": "0" * 40,
        "municipality_source": {"raw_payload_sha256": "a" * 64, "feature_count": 19},
        "municipality_coverage": {"transport_feature_ids": {"x": "volatile"}, "coverage_ratio": 1.0},
        "semantic_sha256": "b" * 64,
        "cell": {"grid_cell_id": module.TARGET_CELL_ID},
    }
    basis = module._semantic_basis(result)
    assert "production_base_sha" not in basis
    assert "raw_payload_sha256" not in basis["municipality_source"]
    assert "transport_feature_ids" not in basis["municipality_coverage"]
    assert "semantic_sha256" not in basis
    assert basis["cell"]["grid_cell_id"] == module.TARGET_CELL_ID
