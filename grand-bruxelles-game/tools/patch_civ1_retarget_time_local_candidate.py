#!/usr/bin/env python3
"""Build QA-only time-local CIV-1 RightFoot retarget counterfactuals.

The validated full rest-direction correction fixes RightFoot phase but regresses planted
horizontal drift when applied globally. This transformer keeps the full source-derived
RightFoot rest direction available, but applies it only in a circular sample window around
the independently measured source plant. The per-sample interpolated rest vector is
renormalized to preserve the original RightFoot length. LeftFoot remains unchanged.
"""
from __future__ import annotations

import argparse
from pathlib import Path

RIGHT = "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
LEFT = "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
SAMPLE = "        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n"
MARKER = "CIV1_RETARGET_TIME_LOCAL_CANDIDATE"
CYCLE_SAMPLES = 120
MAX_RADIUS = 12


def transform(text: str, center_sample: int, radius: int) -> str:
    if isinstance(center_sample, bool) or not isinstance(center_sample, int) or not 0 <= center_sample < CYCLE_SAMPLES:
        raise ValueError(f"center_sample must be an integer in [0, {CYCLE_SAMPLES - 1}]")
    if isinstance(radius, bool) or not isinstance(radius, int) or not 1 <= radius <= MAX_RADIUS:
        raise ValueError(f"radius must be an integer in [1, {MAX_RADIUS}]")
    if MARKER in text:
        raise ValueError("input already contains a time-local candidate")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    if text.count(RIGHT) != 1 or text.count(LEFT) != 1 or text.count(SAMPLE) != 1:
        raise ValueError("validated time-local anchors drifted")
    right = (f"    # {MARKER} center_sample={center_sample} radius={radius}\n" f"    var right_time_local_center: int = {center_sample}\n" f"    var right_time_local_radius: int = {radius}\n" "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n")
    left = "    # Time-local candidates intentionally leave LeftFoot rest translation unchanged.\n    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n"
    sample = "        var right_time_local_forward: int = posmod(sample_idx - right_time_local_center, SAMPLE_COUNT - 1)\n        var right_time_local_backward: int = posmod(right_time_local_center - sample_idx, SAMPLE_COUNT - 1)\n        var right_time_local_distance: int = min(right_time_local_forward, right_time_local_backward)\n        var right_time_local_weight: float = 0.0\n        if right_time_local_distance <= right_time_local_radius:\n            var right_time_local_u: float = float(right_time_local_distance) / float(right_time_local_radius + 1)\n            right_time_local_weight = 0.5 + 0.5 * cos(PI * right_time_local_u)\n        var right_time_local_blend := target_local_rest_origin.lerp(normalized_target_local_rest_origin, right_time_local_weight)\n        if right_time_local_blend.length() <= 0.000000001:\n            push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: time-local candidate produced degenerate RightFoot rest\")\n            quit(14)\n            return\n        var right_time_local_sample_rest := right_time_local_blend.normalized() * target_local_rest_origin.length()\n        if abs(right_time_local_sample_rest.length() - target_local_rest_origin.length()) > 0.000000001:\n            push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: time-local candidate changed RightFoot length\")\n            quit(15)\n            return\n        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * right_time_local_sample_rest\n"
    out = text.replace(RIGHT, right, 1).replace(LEFT, left, 1).replace(SAMPLE, sample, 1)
    if out.count(MARKER) != 1: raise ValueError("time-local candidate marker insertion failed")
    return out

def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("input",type=Path); parser.add_argument("output",type=Path); parser.add_argument("--center-sample",type=int,required=True); parser.add_argument("--radius",type=int,required=True); args=parser.parse_args(); args.output.write_text(transform(args.input.read_text(encoding="utf-8"),args.center_sample,args.radius),encoding="utf-8"); print(f"CIV1_RETARGET_TIME_LOCAL_CANDIDATE_OK center_sample={args.center_sample} radius={args.radius}"); return 0
if __name__ == "__main__": raise SystemExit(main())
