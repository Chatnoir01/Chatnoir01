#!/usr/bin/env python3
"""Build QA-only CIV-1 RightFoot pitch-space retarget counterfactuals.

This family is intentionally different from the rejected rest-translation, axis-Z,
yaw and bounded rest-blend candidates. It rotates the original target RightFoot
local rest vector around local X toward the YZ pitch of the validated source-derived
direction, preserving the original X component and total vector length analytically.
LeftFoot remains untouched. This is diagnostic-only and never authorizes runtime.
"""
from __future__ import annotations

import argparse
from pathlib import Path

RIGHT = "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
LEFT = "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
MARKER = "CIV1_RETARGET_PITCH_CANDIDATE"


def transform(text: str, fraction: float) -> str:
    if isinstance(fraction, bool) or not isinstance(fraction, (int, float)):
        raise ValueError("fraction must be numeric")
    fraction = float(fraction)
    if not 0.0 < fraction < 1.0:
        raise ValueError("fraction must be strictly inside (0, 1)")
    if MARKER in text:
        raise ValueError("input already contains a pitch candidate")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    if text.count(RIGHT) != 1 or text.count(LEFT) != 1:
        raise ValueError("validated pitch anchors drifted")

    replacement = f'''    # {MARKER} fraction={fraction:.6f}\n    var right_pitch_fraction: float = {fraction:.17g}\n    var right_original_x: float = target_local_rest_origin.x\n    var right_original_yz := Vector2(target_local_rest_origin.y, target_local_rest_origin.z)\n    var right_source_yz := Vector2(normalized_target_local_direction.y, normalized_target_local_direction.z)\n    if right_original_yz.length() <= 0.000000001 or right_source_yz.length() <= 0.000000001:\n        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: pitch candidate has degenerate YZ projection")\n        quit(16)\n        return\n    var right_original_angle: float = atan2(right_original_yz.y, right_original_yz.x)\n    var right_source_angle: float = atan2(right_source_yz.y, right_source_yz.x)\n    var right_delta: float = wrapf(right_source_angle - right_original_angle, -PI, PI)\n    var right_pitch_angle: float = right_original_angle + right_delta * right_pitch_fraction\n    var right_yz_radius: float = right_original_yz.length()\n    var right_pitch_raw := Vector3(right_original_x, cos(right_pitch_angle) * right_yz_radius, sin(right_pitch_angle) * right_yz_radius)\n    if right_pitch_raw.length() <= 0.000000001:\n        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: pitch candidate produced degenerate RightFoot rest")\n        quit(17)\n        return\n    var normalized_target_local_rest_origin := right_pitch_raw.normalized() * target_local_rest_origin.length()\n    if abs(normalized_target_local_rest_origin.length() - target_local_rest_origin.length()) > 0.000000001:\n        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: pitch candidate changed RightFoot length")\n        quit(18)\n        return\n'''
    left = "    # Pitch candidates intentionally leave LeftFoot rest translation unchanged.\n    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n"
    out = text.replace(RIGHT, replacement, 1).replace(LEFT, left, 1)
    if out.count(MARKER) != 1:
        raise ValueError("pitch candidate marker insertion failed")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fraction", type=float, required=True)
    args = parser.parse_args()
    args.output.write_text(transform(args.input.read_text(encoding="utf-8"), args.fraction), encoding="utf-8")
    print(f"CIV1_RETARGET_PITCH_CANDIDATE_OK fraction={args.fraction}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
