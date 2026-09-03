#!/usr/bin/env python3
"""Build QA-only CIV-1 RightFoot yaw-space counterfactuals from the validated bilateral shadow probe.

The candidate rotates only the RightFoot local XZ heading toward the source-derived target heading.
It preserves the original local Y component, the original XZ radius, and therefore total foot-rest
length. LeftFoot remains unchanged and is still measured as the bilateral control.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

RIGHT = "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
LEFT = "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
MARKER = "CIV1_RETARGET_YAW_CANDIDATE"


def transform(text: str, fraction: float) -> str:
    if not math.isfinite(fraction) or not 0.0 < fraction < 1.0:
        raise ValueError("fraction must be finite and strictly between 0 and 1")
    if MARKER in text:
        raise ValueError("input already contains a yaw candidate")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    if text.count(RIGHT) != 1 or text.count(LEFT) != 1:
        raise ValueError("validated rest-direction anchors drifted")

    right = (
        f"    # {MARKER} fraction={fraction:.6f}\n"
        f"    var right_yaw_fraction: float = {fraction:.12f}\n"
        "    var right_yaw_horizontal_radius: float = Vector2(target_local_rest_origin.x, target_local_rest_origin.z).length()\n"
        "    if right_yaw_horizontal_radius <= 0.000000001:\n"
        "        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: yaw candidate has degenerate RightFoot XZ radius\")\n"
        "        quit(14)\n"
        "        return\n"
        "    var right_yaw_baseline: float = atan2(target_local_rest_origin.z, target_local_rest_origin.x)\n"
        "    var right_yaw_target: float = atan2(normalized_target_local_direction.z, normalized_target_local_direction.x)\n"
        "    var right_yaw_delta: float = wrapf(right_yaw_target - right_yaw_baseline, -PI, PI)\n"
        "    var right_yaw_angle: float = right_yaw_baseline + right_yaw_delta * right_yaw_fraction\n"
        "    var right_yaw_candidate := Vector3(\n"
        "        cos(right_yaw_angle) * right_yaw_horizontal_radius,\n"
        "        target_local_rest_origin.y,\n"
        "        sin(right_yaw_angle) * right_yaw_horizontal_radius\n"
        "    )\n"
        "    if abs(right_yaw_candidate.length() - target_local_rest_origin.length()) > 0.000000001:\n"
        "        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: yaw candidate changed RightFoot length\")\n"
        "        quit(15)\n"
        "        return\n"
        "    if abs(right_yaw_candidate.y - target_local_rest_origin.y) > 0.000000000001:\n"
        "        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: yaw candidate changed RightFoot local Y\")\n"
        "        quit(16)\n"
        "        return\n"
        "    var normalized_target_local_rest_origin := right_yaw_candidate\n"
    )
    left = (
        "    # Yaw-space candidates intentionally leave LeftFoot rest translation unchanged.\n"
        "    # LeftFoot remains the identical-window bilateral grounding control.\n"
        "    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n"
    )
    out = text.replace(RIGHT, right, 1).replace(LEFT, left, 1)
    if out.count(MARKER) != 1:
        raise ValueError("yaw candidate marker insertion failed")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fraction", type=float, required=True)
    args = parser.parse_args()
    args.output.write_text(transform(args.input.read_text(encoding="utf-8"), args.fraction), encoding="utf-8")
    print(f"CIV1_RETARGET_YAW_CANDIDATE_OK fraction={args.fraction:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
