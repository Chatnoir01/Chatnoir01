#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "data/qa/gate8_alpha0125_player_ab_review_contract.json"
MECHANICAL = ROOT / "data/qa/gate8_one_ring_blend_candidate_contract.json"


def require_sha256(value: str, *, prefixed: bool = False) -> None:
    if prefixed:
        assert value.startswith("sha256:")
        value = value[7:]
    assert len(value) == 64
    assert all(ch in "0123456789abcdef" for ch in value)


def main() -> None:
    c = json.loads(CONTRACT.read_text())
    m = json.loads(MECHANICAL.read_text())

    assert c["schema"] == "grand-bruxelles-gate8-alpha0125-player-ab-review-v1"
    assert c["contract_base_sha"] == "f2da5552898d1db4884b4e2983a6092070d203d1"
    e = c["evidence"]
    assert e["workflow_run_id"] == 33294351954
    assert e["head_sha"] == "974c864164112b53bb93ddb7351df512ceaac5fd"
    assert e["artifact_id"] == 9726974286
    require_sha256(e["artifact_digest"], prefixed=True)
    assert e["run_conclusion"] == "failure_after_artifact_upload_cleanup_only"
    assert e["engine"] == "Godot 4.7.1 stable"
    assert e["blender"] == "4.2.23 LTS"
    assert e["mpfb"] == "2.0.17"
    require_sha256(e["source_pack_sha256"])
    assert e["variant"] == "npc_gate_01"
    assert e["alpha"] == 0.125
    assert e["resolution"] == [1280, 720]
    assert e["frozen_pose_local_z_degrees"] == {
        "upperarm_r": 35.0,
        "clavicle_r": 12.0,
        "spine_03": 4.0,
        "spine_02": 2.0,
    }

    frames = c["frames"]
    assert [row["view"] for row in frames] == [
        "2m-three-quarter", "2m-front", "5m-front", "8m-front"
    ]
    exact_changed = [
        0.00015625,
        0.00005099826388888889,
        0.0000010850694444444444,
        0.000002170138888888889,
    ]
    exact_max = [
        0.4549019607843137,
        0.0784313725490196,
        0.25098039215686274,
        0.3176470588235294,
    ]
    for row, changed, max_delta in zip(frames, exact_changed, exact_max, strict=True):
        assert math.isclose(row["changed_pixel_fraction"], changed, rel_tol=0.0, abs_tol=1e-18)
        assert math.isclose(row["max_abs_rgb_delta"], max_delta, rel_tol=0.0, abs_tol=1e-15)
        require_sha256(row["baseline_sha256"])
        require_sha256(row["candidate_sha256"])
        assert row["baseline_sha256"] != row["candidate_sha256"]
    require_sha256(c["player_ab_json_sha256"])

    review = c["human_full_frame_review"]
    assert review["performed"] is True
    assert review["all_eight_frames_inspected"] is True
    assert review["gross_new_deformation"] is False
    assert review["visible_credibility_improvement_at_2m"] is False
    assert review["visible_credibility_improvement_at_5m"] is False
    assert review["visible_credibility_improvement_at_8m"] is False
    assert review["verdict"] == "JETER_AS_PRODUCTION_VISUAL_FIX_KEEP_AS_MECHANICAL_DIAGNOSTIC"

    assert m["verdict"] == "FREEZE_ALPHA_0_125_AS_MECHANICAL_CANDIDATE_ONLY"
    selected = m["selected_candidate"]
    mech = c["mechanical_context"]
    assert selected["alpha"] == e["alpha"]
    assert mech["critical_edge_mean_abs_strain_before"] == m["stored_baseline"]["critical_edge_mean_abs_strain"]
    assert mech["critical_edge_mean_abs_strain_after"] == selected["critical_edge_mean_abs_strain"]
    assert mech["critical_reduction_fraction"] == selected["critical_reduction_fraction"]
    assert mech["focus_vertex_max_delta_m"] == selected["focus_vertex_max_delta_m"]
    assert mech["inversion_count"] == selected["inversion_count"] == 0

    auth = c["authorization"]
    assert auth and all(value is False for value in auth.values())
    assert c["next_safe_axis"] == "REJECT_UNIFORM_ALPHA0125_VISUAL_FIX_AND_TEST_A_MORE_LOCAL_TOPOLOGY_OR_SOURCE_FIT_CORRECTION_WITH_VISIBLE_2M_EVIDENCE"
    print("GATE8_ALPHA0125_PLAYER_AB_REVIEW_CONTRACT_OK verdict=JETER_AS_PRODUCTION_VISUAL_FIX_KEEP_AS_MECHANICAL_DIAGNOSTIC")


if __name__ == "__main__":
    main()
