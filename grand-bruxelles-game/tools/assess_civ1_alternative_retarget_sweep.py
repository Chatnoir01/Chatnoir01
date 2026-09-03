#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path

KNOWN_BASELINE_PHASE = 27
EXPECTED_SAMPLES = 5


def _finite_non_negative(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)) or float(value) < 0.0:
        raise ValueError(f"{label} must be finite and non-negative")
    return float(value)


def _foot(candidate, foot):
    data = candidate.get("feet", {}).get(foot)
    if not isinstance(data, dict):
        raise ValueError(f"missing {foot} metrics")
    if data.get("sample_count") != EXPECTED_SAMPLES:
        raise ValueError(f"{foot} sample_count must be {EXPECTED_SAMPLES}")
    baseline = _finite_non_negative(data.get("baseline_horizontal_drift_m"), f"{foot}.baseline_horizontal_drift_m")
    measured = _finite_non_negative(data.get("candidate_horizontal_drift_m"), f"{foot}.candidate_horizontal_drift_m")
    vertical = _finite_non_negative(data.get("candidate_vertical_span_m"), f"{foot}.candidate_vertical_span_m")
    if baseline == 0.0:
        ratio = 0.0 if measured == 0.0 else math.inf
    else:
        ratio = measured / baseline
    return {"baseline": baseline, "candidate": measured, "vertical": vertical, "ratio": ratio}


def assess(payload):
    if payload.get("schema") != "grand-bruxelles-civ1-alternative-retarget-sweep-v1":
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
    seen = set(); evaluated = []
    for candidate in candidates:
        cid = candidate.get("candidate_id")
        if not isinstance(cid, str) or not cid.strip() or cid in seen:
            raise ValueError("candidate_id must be unique and non-empty")
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
        phase_fixed = abs(normalized) < 12
        length_preserved = length_error <= 1e-6
        no_horizontal_regression = left["candidate"] <= left["baseline"] + 1e-9 and right["candidate"] <= right["baseline"] + 1e-9
        eligible = phase_fixed and length_preserved and no_horizontal_regression
        worst_ratio = max(left["ratio"], right["ratio"])
        evaluated.append({
            "candidate_id": cid,
            "eligible": eligible,
            "phase_delta_samples": normalized,
            "length_preserved": length_preserved,
            "no_horizontal_regression": no_horizontal_regression,
            "left_ratio": left["ratio"],
            "right_ratio": right["ratio"],
            "worst_horizontal_ratio": worst_ratio,
        })
    eligible = [row for row in evaluated if row["eligible"]]
    eligible.sort(key=lambda row: (row["worst_horizontal_ratio"], abs(row["phase_delta_samples"]), row["candidate_id"]))
    selected = eligible[0]["candidate_id"] if eligible else None
    verdict = "ALLOW_QA_PLAYER_VIEW_CAPTURE" if selected else "BLOCK_NO_NONREGRESSING_RETARGET_CANDIDATE"
    return {
        "schema": "grand-bruxelles-civ1-alternative-retarget-sweep-assessment-v1",
        "verdict": verdict,
        "selected_candidate_id": selected,
        "evaluated_candidates": evaluated,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main():
    p = argparse.ArgumentParser(); p.add_argument("input", type=Path); p.add_argument("output", type=Path)
    a = p.parse_args(); result = assess(json.loads(a.input.read_text())); a.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(result["verdict"]); return 0

if __name__ == "__main__":
    raise SystemExit(main())
