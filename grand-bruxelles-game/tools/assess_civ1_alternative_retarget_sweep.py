#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path

KNOWN_BASELINE_PHASE = 27
EXPECTED_SAMPLES = 5
BASELINE_MATCH_TOLERANCE_M = 1e-12
DRIFT_TOLERANCE_M = 1e-9


def _finite_non_negative(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) < 0.0:
        raise ValueError(f"{label} must be finite and non-negative")
    return float(value)


def _sample_indices(data, foot):
    samples = data.get("planted_sample_indices")
    cycle = data.get("animation_cycle_sample_count")
    if isinstance(cycle, bool) or not isinstance(cycle, int) or cycle < EXPECTED_SAMPLES:
        raise ValueError(f"{foot}.animation_cycle_sample_count must be an integer >= {EXPECTED_SAMPLES}")
    if not isinstance(samples, list) or len(samples) != EXPECTED_SAMPLES:
        raise ValueError(f"{foot}.planted_sample_indices must contain exactly {EXPECTED_SAMPLES} entries")
    normalized = []
    for value in samples:
        if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value >= cycle:
            raise ValueError(f"{foot}.planted_sample_indices must be integer indices inside the animation cycle")
        normalized.append(value)
    if len(set(normalized)) != EXPECTED_SAMPLES:
        raise ValueError(f"{foot}.planted_sample_indices must be unique")
    for previous, current in zip(normalized, normalized[1:]):
        if current != (previous + 1) % cycle:
            raise ValueError(f"{foot}.planted_sample_indices must be one chronological five-sample cyclic window")
    return tuple(normalized), cycle


def _foot(candidate, foot):
    data = candidate.get("feet", {}).get(foot)
    if not isinstance(data, dict):
        raise ValueError(f"missing {foot} metrics")
    if isinstance(data.get("sample_count"), bool) or data.get("sample_count") != EXPECTED_SAMPLES:
        raise ValueError(f"{foot} sample_count must be {EXPECTED_SAMPLES}")
    samples, cycle = _sample_indices(data, foot)
    baseline_h = _finite_non_negative(data.get("baseline_horizontal_drift_m"), f"{foot}.baseline_horizontal_drift_m")
    measured_h = _finite_non_negative(data.get("candidate_horizontal_drift_m"), f"{foot}.candidate_horizontal_drift_m")
    baseline_v = _finite_non_negative(data.get("baseline_vertical_span_m"), f"{foot}.baseline_vertical_span_m")
    measured_v = _finite_non_negative(data.get("candidate_vertical_span_m"), f"{foot}.candidate_vertical_span_m")
    h_ratio = 0.0 if baseline_h == 0.0 and measured_h == 0.0 else (math.inf if baseline_h == 0.0 else measured_h / baseline_h)
    v_ratio = 0.0 if baseline_v == 0.0 and measured_v == 0.0 else (math.inf if baseline_v == 0.0 else measured_v / baseline_v)
    return {"samples": samples, "cycle": cycle, "baseline_h": baseline_h, "candidate_h": measured_h, "baseline_v": baseline_v, "candidate_v": measured_v, "h_ratio": h_ratio, "v_ratio": v_ratio}


def _require_shared_baseline(reference, current, cid):
    if reference is None:
        return {foot: {"samples": current[foot]["samples"], "cycle": current[foot]["cycle"], "h": current[foot]["baseline_h"], "v": current[foot]["baseline_v"]} for foot in ("LeftFoot", "RightFoot")}
    for foot in ("LeftFoot", "RightFoot"):
        if current[foot]["cycle"] != reference[foot]["cycle"]:
            raise ValueError(f"{cid}: {foot} animation cycle differs across candidates")
        if current[foot]["samples"] != reference[foot]["samples"]:
            raise ValueError(f"{cid}: {foot} planted sample indices differ across candidates")
        if abs(current[foot]["baseline_h"] - reference[foot]["h"]) > BASELINE_MATCH_TOLERANCE_M:
            raise ValueError(f"{cid}: {foot} horizontal baseline differs across candidates")
        if abs(current[foot]["baseline_v"] - reference[foot]["v"]) > BASELINE_MATCH_TOLERANCE_M:
            raise ValueError(f"{cid}: {foot} vertical baseline differs across candidates")
    return reference


def assess(payload):
    if payload.get("schema") != "grand-bruxelles-civ1-alternative-retarget-sweep-v2":
        raise ValueError("unexpected schema")
    if payload.get("godot_version") != "4.7.1":
        raise ValueError("Godot 4.7.1 evidence required")
    if payload.get("same_animation_window") is not True:
        raise ValueError("same_animation_window must be true")
    if payload.get("runtime_authorized") is not False or payload.get("visual_approval_claimed") is not False:
        raise ValueError("QA-only rails must remain closed")
    candidates = payload.get("candidates")
    if not isinstance(candidates, list) or len(candidates) < 2:
        raise ValueError("at least two alternative candidates are required")
    seen = set(); evaluated = []; shared_baseline = None
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise ValueError("each candidate must be an object")
        raw_cid = candidate.get("candidate_id")
        if not isinstance(raw_cid, str) or not raw_cid.strip():
            raise ValueError("candidate_id must be non-empty")
        cid = raw_cid.strip()
        if cid != raw_cid or cid in seen:
            raise ValueError("candidate_id must be canonical and unique")
        seen.add(cid)
        if candidate.get("counterfactual_only") is not True:
            raise ValueError(f"{cid}: counterfactual_only must be true")
        if candidate.get("rightfoot_baseline_phase_delta_samples") != KNOWN_BASELINE_PHASE:
            raise ValueError(f"{cid}: baseline RightFoot phase must remain +27")
        normalized = candidate.get("rightfoot_candidate_phase_delta_samples")
        if isinstance(normalized, bool) or not isinstance(normalized, int):
            raise ValueError(f"{cid}: candidate phase delta must be integer")
        length_error = _finite_non_negative(candidate.get("rightfoot_length_error_m"), f"{cid}.rightfoot_length_error_m")
        left = _foot(candidate, "LeftFoot"); right = _foot(candidate, "RightFoot")
        shared_baseline = _require_shared_baseline(shared_baseline, {"LeftFoot": left, "RightFoot": right}, cid)
        phase_fixed = abs(normalized) < 12
        length_preserved = length_error <= 1e-6
        no_horizontal_regression = all(x["candidate_h"] <= x["baseline_h"] + DRIFT_TOLERANCE_M for x in (left, right))
        no_vertical_regression = all(x["candidate_v"] <= x["baseline_v"] + DRIFT_TOLERANCE_M for x in (left, right))
        eligible = phase_fixed and length_preserved and no_horizontal_regression and no_vertical_regression
        worst_ratio = max(left["h_ratio"], right["h_ratio"], left["v_ratio"], right["v_ratio"])
        evaluated.append({"candidate_id": cid, "eligible": eligible, "phase_delta_samples": normalized, "length_preserved": length_preserved, "no_horizontal_regression": no_horizontal_regression, "no_vertical_regression": no_vertical_regression, "left_horizontal_ratio": left["h_ratio"], "right_horizontal_ratio": right["h_ratio"], "left_vertical_ratio": left["v_ratio"], "right_vertical_ratio": right["v_ratio"], "worst_grounding_ratio": worst_ratio})
    eligible = [row for row in evaluated if row["eligible"]]
    eligible.sort(key=lambda row: (row["worst_grounding_ratio"], abs(row["phase_delta_samples"]), row["candidate_id"]))
    selected = eligible[0]["candidate_id"] if eligible else None
    return {"schema": "grand-bruxelles-civ1-alternative-retarget-sweep-assessment-v2", "verdict": "ALLOW_QA_PLAYER_VIEW_CAPTURE" if selected else "BLOCK_NO_NONREGRESSING_RETARGET_CANDIDATE", "selected_candidate_id": selected, "evaluated_candidates": evaluated, "runtime_authorized": False, "visual_approval_claimed": False}


def main():
    p = argparse.ArgumentParser(); p.add_argument("input", type=Path); p.add_argument("output", type=Path)
    a = p.parse_args(); result = assess(json.loads(a.input.read_text())); a.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(result["verdict"]); return 0

if __name__ == "__main__":
    raise SystemExit(main())
