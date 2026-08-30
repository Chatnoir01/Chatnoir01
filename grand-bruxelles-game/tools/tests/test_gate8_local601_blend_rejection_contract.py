from __future__ import annotations

import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
CONTRACT = PROJECT / "data/qa/gate8_local601_blend_rejection_contract.json"


def load_contract() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


def test_local601_blend_family_remains_rejected_fail_closed() -> None:
    c = load_contract()
    assert c["schema"] == "grand-bruxelles-gate8-local601-blend-rejection-v1"
    assert c["production_base_sha"] == "b293bf94de8ba1e4c9893295b6ebb6487b131c7c"
    assert c["source_run_id"] == 33285324003
    assert c["artifact"] == {
        "id": 9724240116,
        "name": "gate8-local601-blend-sweep-v1-red-first",
        "digest": "sha256:b9d981c8729052c9cd8ea3a37aeeaaac4b05b3fd3a6e877a669bb3f21b79fa06",
    }
    assert c["generator"]["blender"] == "4.2.23 LTS"
    assert c["generator"]["mpfb"] == "2.0.17"
    assert c["candidate_strategy"] == "LINEAR_BLEND_STORED_TO_REMATCHED_WEIGHTS_AT_VERTEX_601_ONLY"
    assert c["verdict"] == "REJECT_SINGLE_VERTEX_601_BLEND_FAMILY_FOR_PRODUCTION"
    assert c["next_safe_axis"] == "MULTI_VERTEX_TOPOLOGY_CONSTRAINED_SUPPORT"

    baseline = c["stored_baseline"]
    candidates = c["candidates"]
    assert [row["alpha"] for row in candidates] == [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
    assert all(row["inversions"] == 0 for row in candidates)
    assert all(row["critical_edge_mean_abs_strain"] < baseline["critical_edge_mean_abs_strain"] for row in candidates)
    assert all(row["control_edge_mean_abs_strain"] > baseline["control_edge_mean_abs_strain"] for row in candidates)
    assert all(row["control_edge_378_601_abs_strain"] > baseline["control_edge_378_601_abs_strain"] for row in candidates)
    assert all(row["vertex_601_delta_m"] > 0 for row in candidates)

    safest = candidates[0]
    assert safest["control_edge_mean_abs_strain"] / baseline["control_edge_mean_abs_strain"] > 5.46
    assert safest["control_edge_378_601_abs_strain"] / baseline["control_edge_378_601_abs_strain"] > 6.23
    critical_reduction = 1.0 - safest["critical_edge_mean_abs_strain"] / baseline["critical_edge_mean_abs_strain"]
    assert 0.112 < critical_reduction < 0.114

    auth = c["authorization"]
    for key in (
        "canonical_asset_mutation",
        "mhclo_mutation",
        "generator_mutation",
        "runtime_npc_mutation",
        "reweight_authorized",
        "retarget_authorized",
        "production_activation",
        "visual_approval",
    ):
        assert auth[key] is False, key
