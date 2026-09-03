#!/usr/bin/env python3
from __future__ import annotations
import copy, importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("assessor", ROOT / "tools" / "assess_civ1_alternative_retarget_sweep.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)


def foot(base_h, cand_h, base_v, cand_v):
    return {"sample_count": 5, "baseline_horizontal_drift_m": base_h, "candidate_horizontal_drift_m": cand_h, "baseline_vertical_span_m": base_v, "candidate_vertical_span_m": cand_v}

BASE = {
    "schema": "grand-bruxelles-civ1-alternative-retarget-sweep-v2",
    "godot_version": "4.7.1", "same_animation_window": True,
    "runtime_authorized": False, "visual_approval_claimed": False,
    "candidates": [
        {"candidate_id":"rest_direction_full","counterfactual_only":True,"rightfoot_baseline_phase_delta_samples":27,"rightfoot_candidate_phase_delta_samples":0,"rightfoot_length_error_m":0.0,"feet":{"LeftFoot":foot(.00605985,.00655274,.010,.010),"RightFoot":foot(.02824156,.02988819,.01130581,.01107949)}},
        {"candidate_id":"rest_direction_partial_qa","counterfactual_only":True,"rightfoot_baseline_phase_delta_samples":27,"rightfoot_candidate_phase_delta_samples":8,"rightfoot_length_error_m":0.0,"feet":{"LeftFoot":foot(.00605985,.00600,.010,.0099),"RightFoot":foot(.02824156,.02750,.01130581,.0110)}}
    ]}

def expect_error(payload):
    try: MOD.assess(payload)
    except ValueError: return
    raise AssertionError("expected fail-closed ValueError")

def main():
    r = MOD.assess(copy.deepcopy(BASE)); assert r["verdict"] == "ALLOW_QA_PLAYER_VIEW_CAPTURE"; assert r["selected_candidate_id"] == "rest_direction_partial_qa"
    bad = copy.deepcopy(BASE); bad["candidates"][1]["feet"]["RightFoot"]["candidate_horizontal_drift_m"] = .030; assert MOD.assess(bad)["verdict"].startswith("BLOCK_")
    vertical = copy.deepcopy(BASE); vertical["candidates"][1]["feet"]["LeftFoot"]["candidate_vertical_span_m"] = .020; assert MOD.assess(vertical)["verdict"].startswith("BLOCK_")
    forged_v = copy.deepcopy(BASE); forged_v["candidates"][1]["feet"]["RightFoot"]["baseline_vertical_span_m"] = .5; expect_error(forged_v)
    forged_h = copy.deepcopy(BASE); forged_h["candidates"][1]["feet"]["LeftFoot"]["baseline_horizontal_drift_m"] = .5; expect_error(forged_h)
    spaced = copy.deepcopy(BASE); spaced["candidates"][1]["candidate_id"] = " rest_direction_partial_qa"; expect_error(spaced)
    nan = copy.deepcopy(BASE); nan["candidates"][1]["feet"]["LeftFoot"]["candidate_vertical_span_m"] = float("nan"); expect_error(nan)
    phase = copy.deepcopy(BASE); phase["candidates"][1]["rightfoot_candidate_phase_delta_samples"] = 12; assert MOD.assess(phase)["verdict"].startswith("BLOCK_")
    rails = copy.deepcopy(BASE); rails["runtime_authorized"] = True; expect_error(rails)
    print("CIV1_ALTERNATIVE_RETARGET_SWEEP_V2_TEST_OK")
    return 0

if __name__ == "__main__": raise SystemExit(main())
