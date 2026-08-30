from __future__ import annotations

import json
import math
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
CONTRACT = PROJECT / "data/qa/gate8_one_ring_blend_candidate_contract.json"


def load_contract() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


def test_one_ring_candidate_is_measured_unique_and_fail_closed() -> None:
    c = load_contract()
    assert c["schema"] == "grand-bruxelles-gate8-one-ring-blend-candidate-v1"
    assert c["production_base_sha"] == "5711ca48ac08d9e27e1263d44eb1898e52ee6fd9"
    assert c["source_run_id"] == 33287685742
    assert c["source_head_sha"] == "62c2e641898e895b46b87398dd396237a5359483"
    assert c["artifact"] == {
        "id": 9724959018,
        "name": "gate8-one-ring-blend-sweep-v1-red-first",
        "digest": "sha256:1c56a65c28cf07f52ea682f3a808edf1d25be4c555917f9c57e11f1d4ad3567a",
    }
    assert c["generator"] == {
        "blender": "4.2.23 LTS",
        "mpfb": "2.0.17",
        "mpfb_build": "20260722",
        "source_pack_sha256": "6b1d673e4c1fd169372d3a74fe174d9c185069c1f55ff6bf6b224f6655e4b67a",
    }
    assert c["candidate_strategy"] == "UNIFORM_LINEAR_BLEND_STORED_TO_REMATCHED_WEIGHTS_ACROSS_REVIEWED_ONE_RING"
    assert c["focus_vertices"] == [377, 378, 379, 486, 599, 601, 615, 864]

    baseline = c["stored_baseline"]
    candidates = c["measured_candidates"]
    assert [row["alpha"] for row in candidates] == [0.0625, 0.125, 0.25, 0.375, 0.5]
    assert all(row["inversion_count"] == 0 for row in candidates)
    assert all(row["focus_vertex_max_delta_m"] > 0.0 for row in candidates)

    pareto = [
        row for row in candidates
        if row["critical_edge_mean_abs_strain"] < baseline["critical_edge_mean_abs_strain"]
        and row["control_edge_mean_abs_strain"] < baseline["control_edge_mean_abs_strain"]
        and row["control_edge_378_601_abs_strain"] < baseline["control_edge_378_601_abs_strain"]
        and row["inversion_count"] == 0
    ]
    assert [row["alpha"] for row in pareto] == [0.125]

    selected = c["selected_candidate"]
    measured = pareto[0]
    for key in (
        "alpha",
        "critical_edge_mean_abs_strain",
        "control_edge_mean_abs_strain",
        "control_edge_378_601_abs_strain",
        "focus_vertex_max_delta_m",
        "focus_vertex_mean_delta_m",
        "inversion_count",
    ):
        assert selected[key] == measured[key], key

    assert math.isclose(
        selected["critical_reduction_fraction"],
        1.0 - selected["critical_edge_mean_abs_strain"] / baseline["critical_edge_mean_abs_strain"],
        rel_tol=0.0,
        abs_tol=1e-15,
    )
    assert math.isclose(
        selected["control_mean_reduction_fraction"],
        1.0 - selected["control_edge_mean_abs_strain"] / baseline["control_edge_mean_abs_strain"],
        rel_tol=0.0,
        abs_tol=1e-15,
    )
    assert math.isclose(
        selected["control_378_601_reduction_fraction"],
        1.0 - selected["control_edge_378_601_abs_strain"] / baseline["control_edge_378_601_abs_strain"],
        rel_tol=0.0,
        abs_tol=1e-15,
    )
    assert 0.14 < selected["critical_reduction_fraction"] < 0.141
    assert 0.005 < selected["control_mean_reduction_fraction"] < 0.0065
    assert 0.58 < selected["control_378_601_reduction_fraction"] < 0.582
    assert selected["focus_vertex_max_delta_m"] > 0.06

    assert c["verdict"] == "FREEZE_ALPHA_0_125_AS_MECHANICAL_CANDIDATE_ONLY"
    assert c["next_safe_axis"] == "ISOLATED_ALPHA_0_125_REAL_POSE_GEOMETRY_PLUS_PLAYER_VIEW_AB"
    auth = c["authorization"]
    assert auth
    assert all(value is False for value in auth.values())
