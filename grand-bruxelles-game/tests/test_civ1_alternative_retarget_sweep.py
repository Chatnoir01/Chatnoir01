#!/usr/bin/env python3
from __future__ import annotations
import copy, importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("assessor", ROOT / "tools" / "assess_civ1_alternative_retarget_sweep.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)

BASE = {
    "schema": "grand-bruxelles-civ1-alternative-retarget-sweep-v1",
    "godot_version": "4.7.1",
    "same_animation_window": True,
    "runtime_authorized": False,
    "visual_approval_claimed": False,
    "candidates": [
        {
            "candidate_id": "rest_direction_full",
            "counterfactual_only": True,
            "rightfoot_baseline_phase_delta_samples": 27,
            "rightfoot_candidate_phase_delta_samples": 0,
            "rightfoot_length_error_m": 0.0,
            "feet": {
                "LeftFoot": {"sample_count": 5, "baseline_horizontal_drift_m": 0.00605985289439559, "candidate_horizontal_drift_m": 0.0065527418628335, "candidate_vertical_span_m": 0.010},
                "RightFoot": {"sample_count": 5, "baseline_horizontal_drift_m": 0.0282415617257357, "candidate_horizontal_drift_m": 0.0298881884664297, "candidate_vertical_span_m": 0.0110794901847839},
            },
        },
        {
            "candidate_id": "rest_direction_partial_qa",
            "counterfactual_only": True,
            "rightfoot_baseline_phase_delta_samples": 27,
            "rightfoot_candidate_phase_delta_samples": 8,
            "rightfoot_length_error_m": 0.0,
            "feet": {
                "LeftFoot": {"sample_count": 5, "baseline_horizontal_drift_m": 0.00605985289439559, "candidate_horizontal_drift_m": 0.00600, "candidate_vertical_span_m": 0.010},
                "RightFoot": {"sample_count": 5, "baseline_horizontal_drift_m": 0.0282415617257357, "candidate_horizontal_drift_m": 0.02750, "candidate_vertical_span_m": 0.011},
            },
        },
    ],
}


def expect_error(payload):
    try: MOD.assess(payload)
    except ValueError: return
    raise AssertionError("expected fail-closed ValueError")


def main():
    result = MOD.assess(copy.deepcopy(BASE))
    assert result["verdict"] == "ALLOW_QA_PLAYER_VIEW_CAPTURE"
    assert result["selected_candidate_id"] == "rest_direction_partial_qa"
    assert result["runtime_authorized"] is False and result["visual_approval_claimed"] is False

    blocked = copy.deepcopy(BASE)
    blocked["candidates"][1]["feet"]["RightFoot"]["candidate_horizontal_drift_m"] = 0.030
    result = MOD.assess(blocked)
    assert result["verdict"] == "BLOCK_NO_NONREGRESSING_RETARGET_CANDIDATE"
    assert result["selected_candidate_id"] is None

    phase_bad = copy.deepcopy(BASE)
    phase_bad["candidates"][1]["rightfoot_candidate_phase_delta_samples"] = 12
    result = MOD.assess(phase_bad)
    assert result["verdict"] == "BLOCK_NO_NONREGRESSING_RETARGET_CANDIDATE"

    forged = copy.deepcopy(BASE); forged["candidates"][1]["rightfoot_length_error_m"] = float("nan")
    expect_error(forged)
    duplicate = copy.deepcopy(BASE); duplicate["candidates"][1]["candidate_id"] = duplicate["candidates"][0]["candidate_id"]
    expect_error(duplicate)
    sample_drift = copy.deepcopy(BASE); sample_drift["candidates"][1]["feet"]["LeftFoot"]["sample_count"] = 4
    expect_error(sample_drift)
    boolean_phase = copy.deepcopy(BASE); boolean_phase["candidates"][1]["rightfoot_candidate_phase_delta_samples"] = True
    expect_error(boolean_phase)
    rails = copy.deepcopy(BASE); rails["runtime_authorized"] = True
    expect_error(rails)
    print("CIV1_ALTERNATIVE_RETARGET_SWEEP_TEST_OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
