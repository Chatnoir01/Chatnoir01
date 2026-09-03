#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("gate",ROOT/"tools"/"assess_civ1_planted_drift.py"); gate=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(gate)

def payload():
    return {
      "runtime_authorized":False,"visual_approval_claimed":False,
      "phase_vertical_summary":{"per_bone":{"RightFoot":{"phase_delta_samples":27}}},
      "right_foot_reference_ab":{"normalized_phase_delta_samples":0,"target_foot_length_preserved":True},
      "locomotion_measurements":{"method":"five_sample_source_vertical_min_window",
        "LeftFoot":{"same_animation_window":True,"baseline":{"planted_sample_count":5,"planted_horizontal_drift_m":0.00605985289439559,"planted_vertical_span_m":0.00333511829376221},"counterfactual":{"planted_sample_count":5,"planted_horizontal_drift_m":0.0065527418628335,"planted_vertical_span_m":0.00625431537628174}},
        "RightFoot":{"same_animation_window":True,"baseline":{"planted_sample_count":5,"planted_horizontal_drift_m":0.0282415617257357,"planted_vertical_span_m":0.0113058090209961},"counterfactual":{"planted_sample_count":5,"planted_horizontal_drift_m":0.0298881884664297,"planted_vertical_span_m":0.0110794901847839}}}}

def main():
    measured=gate.assess(payload())
    assert measured["verdict"]=="BLOCK_COUNTERFACTUAL_LOCOMOTION_REGRESSION"
    assert "rightfoot_planted_horizontal_drift_regressed" in measured["failures"]
    assert "leftfoot_control_horizontal_drift_regressed" in measured["failures"]
    right=measured["feet"]["RightFoot"]
    assert 1.058 < right["horizontal_ratio"] < 1.059
    improved=payload(); improved["locomotion_measurements"]["LeftFoot"]["counterfactual"]["planted_horizontal_drift_m"]=0.0060; improved["locomotion_measurements"]["RightFoot"]["counterfactual"]["planted_horizontal_drift_m"]=0.0280
    assert gate.assess(improved)["verdict"]=="ALLOW_QA_PLAYER_VIEW_CAPTURE"
    weak=payload(); weak["right_foot_reference_ab"]["normalized_phase_delta_samples"]=14
    assert "rightfoot_phase_not_corrected" in gate.assess(weak)["failures"]
    bad=payload(); bad["locomotion_measurements"]["RightFoot"]["baseline"]["planted_horizontal_drift_m"]=float("nan")
    assert "invalid_metric:RightFoot" in gate.assess(bad)["failures"]
    print("CIV1_PLANTED_DRIFT_GATE_TEST_OK"); return 0
if __name__=="__main__": raise SystemExit(main())
