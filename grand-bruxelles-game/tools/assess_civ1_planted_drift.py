#!/usr/bin/env python3
"""Fail-closed QA gate for CIV-1 planted-foot counterfactual consequence.

Consumes the native Godot locomotion diagnostic. It never authorizes runtime mutation.
A phase fix is insufficient if planted horizontal drift regresses.
"""
from __future__ import annotations
import argparse, json, math
from pathlib import Path

FEET=("LeftFoot","RightFoot")

def finite_nonneg(v):
    return isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(float(v)) and v>=0

def assess(payload: dict) -> dict:
    failures=[]; rows={}
    if payload.get("runtime_authorized") is not False: failures.append("runtime_rail_missing")
    if payload.get("visual_approval_claimed") is not False: failures.append("visual_claim_rail_missing")
    phase=payload.get("phase_vertical_summary",{}).get("per_bone",{}).get("RightFoot",{})
    right_ab=payload.get("right_foot_reference_ab",{})
    if phase.get("phase_delta_samples") != 27: failures.append("unexpected_rightfoot_baseline_phase")
    if right_ab.get("normalized_phase_delta_samples") != 0: failures.append("rightfoot_phase_not_corrected")
    if right_ab.get("target_foot_length_preserved") is not True: failures.append("rightfoot_length_not_preserved")
    metrics=payload.get("locomotion_measurements")
    if not isinstance(metrics,dict) or metrics.get("method")!="five_sample_source_vertical_min_window": failures.append("missing_native_locomotion_metrics"); metrics={}
    for foot in FEET:
        row=metrics.get(foot)
        if not isinstance(row,dict): failures.append(f"missing:{foot}"); continue
        if row.get("same_animation_window") is not True: failures.append(f"window_mismatch:{foot}")
        base,cf=row.get("baseline"),row.get("counterfactual")
        if not isinstance(base,dict) or not isinstance(cf,dict): failures.append(f"pair_missing:{foot}"); continue
        vals=[base.get("planted_horizontal_drift_m"),cf.get("planted_horizontal_drift_m"),base.get("planted_vertical_span_m"),cf.get("planted_vertical_span_m")]
        if not all(finite_nonneg(v) for v in vals): failures.append(f"invalid_metric:{foot}"); continue
        if base.get("planted_sample_count")!=5 or cf.get("planted_sample_count")!=5: failures.append(f"sample_count:{foot}")
        h0,h1,v0,v1=map(float,vals)
        rows[foot]={"baseline_horizontal_drift_m":h0,"counterfactual_horizontal_drift_m":h1,"horizontal_delta_m":h1-h0,"horizontal_ratio":(h1/h0 if h0>0 else None),"baseline_vertical_span_m":v0,"counterfactual_vertical_span_m":v1,"vertical_delta_m":v1-v0}
    right=rows.get("RightFoot")
    if right and right["horizontal_delta_m"]>1e-9: failures.append("rightfoot_planted_horizontal_drift_regressed")
    left=rows.get("LeftFoot")
    if left and left["horizontal_delta_m"]>1e-9: failures.append("leftfoot_control_horizontal_drift_regressed")
    verdict="ALLOW_QA_PLAYER_VIEW_CAPTURE" if not failures else "BLOCK_COUNTERFACTUAL_LOCOMOTION_REGRESSION"
    return {"format":"grand-bruxelles-civ1-planted-drift-assessment-v1","feet":rows,"runtime_authorized":False,"visual_approval_claimed":False,"failures":failures,"verdict":verdict}

def main():
    p=argparse.ArgumentParser(); p.add_argument("input",type=Path); p.add_argument("--output",type=Path,required=True); p.add_argument("--expect-verdict"); a=p.parse_args(); r=assess(json.loads(a.input.read_text())); a.output.write_text(json.dumps(r,indent=2,sort_keys=True)+"\n"); print(r["verdict"]); return 0 if not a.expect_verdict or r["verdict"]==a.expect_verdict else 1
if __name__=="__main__": raise SystemExit(main())
