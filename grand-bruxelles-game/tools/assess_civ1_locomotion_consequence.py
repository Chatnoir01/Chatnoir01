#!/usr/bin/env python3
"""Fail-closed CIV-1 locomotion consequence evidence assessor.

This gate deliberately does not authorize a runtime rest patch from phase causality alone.
It requires paired baseline/counterfactual planted-foot measurements plus an unchanged
1280x720 real-player-view capture contract before QA may compare visible consequence.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

FEET = ("LeftFoot", "RightFoot")
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def _number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
    )


def assess(bilateral: dict, locomotion: dict) -> dict:
    failures: list[str] = []
    if bilateral.get("verdict") != "ALLOW_QA_BILATERAL_REST_ATTRIBUTION":
        failures.append("bilateral_causality_not_proven")
    if bilateral.get("runtime_authorized") is not False:
        failures.append("bilateral_runtime_rail_missing")

    if locomotion.get("format") != "grand-bruxelles-civ1-locomotion-consequence-v1":
        failures.append("invalid_locomotion_format")
    if locomotion.get("counterfactual_only") is not True:
        failures.append("counterfactual_contract_missing")
    if locomotion.get("runtime_authorized") is not False:
        failures.append("locomotion_runtime_rail_missing")

    capture = locomotion.get("player_view_capture")
    if not isinstance(capture, dict):
        failures.append("missing_player_view_capture")
    else:
        if capture.get("width") != 1280 or capture.get("height") != 720:
            failures.append("player_view_not_1280x720")
        if capture.get("full_frame") is not True:
            failures.append("player_view_not_full_frame")
        if capture.get("camera_unchanged") is not True:
            failures.append("camera_rescue_detected")
        if capture.get("ai_generated") is not False:
            failures.append("ai_generated_evidence_forbidden")
        frame_sha256 = capture.get("frame_sha256")
        if not isinstance(frame_sha256, str):
            failures.append("missing_frame_sha256")
        elif SHA256_RE.fullmatch(frame_sha256) is None:
            failures.append("invalid_frame_sha256")

    measurements = locomotion.get("feet")
    if not isinstance(measurements, dict):
        failures.append("missing_foot_measurements")
        measurements = {}
    rows = {}
    for foot in FEET:
        row = measurements.get(foot)
        if not isinstance(row, dict):
            failures.append(f"missing_measurement:{foot}")
            continue
        base = row.get("baseline")
        cf = row.get("counterfactual")
        if not isinstance(base, dict) or not isinstance(cf, dict):
            failures.append(f"incomplete_pair:{foot}")
            continue
        for label, sample in (("baseline", base), ("counterfactual", cf)):
            count = sample.get("planted_sample_count")
            horiz = sample.get("planted_horizontal_drift_m")
            vertical = sample.get("planted_vertical_span_m")
            if not isinstance(count, int) or isinstance(count, bool) or count < 3:
                failures.append(f"invalid_sample_count:{foot}:{label}")
            if not _number(horiz) or horiz < 0:
                failures.append(f"invalid_horizontal_drift:{foot}:{label}")
            if not _number(vertical) or vertical < 0:
                failures.append(f"invalid_vertical_span:{foot}:{label}")
        if base.get("planted_sample_count") != cf.get("planted_sample_count"):
            failures.append(f"sample_count_mismatch:{foot}")
        if row.get("same_animation_window") is not True:
            failures.append(f"window_mismatch:{foot}")
        if not any(f.startswith(("invalid_", "incomplete_pair")) and f":{foot}" in f for f in failures):
            rows[foot] = {
                "baseline_horizontal_drift_m": base["planted_horizontal_drift_m"],
                "counterfactual_horizontal_drift_m": cf["planted_horizontal_drift_m"],
                "baseline_vertical_span_m": base["planted_vertical_span_m"],
                "counterfactual_vertical_span_m": cf["planted_vertical_span_m"],
                "planted_sample_count": base["planted_sample_count"],
            }

    complete = not failures
    return {
        "format": "grand-bruxelles-civ1-locomotion-consequence-assessment-v1",
        "measurement_complete": complete,
        "feet": rows,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "failures": failures,
        "verdict": "ALLOW_QA_LOCOMOTION_COMPARISON" if complete else "BLOCK_INCOMPLETE_LOCOMOTION_EVIDENCE",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("bilateral", type=Path)
    parser.add_argument("locomotion", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-verdict")
    args = parser.parse_args()
    result = assess(
        json.loads(args.bilateral.read_text(encoding="utf-8")),
        json.loads(args.locomotion.read_text(encoding="utf-8")),
    )
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(result["verdict"])
    if args.expect_verdict:
        return 0 if result["verdict"] == args.expect_verdict else 1
    return 0 if result["measurement_complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
