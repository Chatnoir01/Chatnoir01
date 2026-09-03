#!/usr/bin/env python3
"""Build QA-only CIV-1 RightFoot axis-decomposition counterfactuals from the validated bilateral shadow probe."""
from __future__ import annotations
import argparse
from pathlib import Path

RIGHT = "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
LEFT = "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
MARKER = "CIV1_RETARGET_AXIS_CANDIDATE"
MODES = {"right_x", "right_z", "right_xz"}


def transform(text: str, mode: str) -> str:
    if mode not in MODES:
        raise ValueError(f"mode must be one of {sorted(MODES)}")
    if MARKER in text:
        raise ValueError("input already contains an axis candidate")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    if text.count(RIGHT) != 1 or text.count(LEFT) != 1:
        raise ValueError("validated rest-direction anchors drifted")
    use_x = "true" if mode in {"right_x", "right_xz"} else "false"
    use_z = "true" if mode in {"right_z", "right_xz"} else "false"
    right = (
        f"    # {MARKER} mode={mode}\n"
        f"    var right_axis_use_x: bool = {use_x}\n"
        f"    var right_axis_use_z: bool = {use_z}\n"
        "    var right_axis_length: float = target_local_rest_origin.length()\n"
        "    var right_axis_x: float = normalized_target_local_direction.x * right_axis_length if right_axis_use_x else target_local_rest_origin.x\n"
        "    var right_axis_z: float = normalized_target_local_direction.z * right_axis_length if right_axis_use_z else target_local_rest_origin.z\n"
        "    var right_axis_y_sq: float = right_axis_length * right_axis_length - right_axis_x * right_axis_x - right_axis_z * right_axis_z\n"
        "    if right_axis_y_sq < -0.000000000001:\n"
        "        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: axis candidate exceeds preserved RightFoot length\")\n"
        "        quit(14)\n"
        "        return\n"
        "    var right_axis_y_sign: float = -1.0 if target_local_rest_origin.y < 0.0 else 1.0\n"
        "    var right_axis_y: float = right_axis_y_sign * sqrt(max(0.0, right_axis_y_sq))\n"
        "    var normalized_target_local_rest_origin := Vector3(right_axis_x, right_axis_y, right_axis_z)\n"
    )
    left = (
        "    # Axis-decomposition candidates intentionally leave LeftFoot rest translation unchanged.\n"
        "    # LeftFoot is still measured on the identical planted window by the bilateral assessor.\n"
        "    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n"
    )
    out = text.replace(RIGHT, right, 1).replace(LEFT, left, 1)
    if out.count(MARKER) != 1:
        raise ValueError("axis candidate marker insertion failed")
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("input", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--mode", choices=sorted(MODES), required=True)
    a = p.parse_args()
    a.output.write_text(transform(a.input.read_text(encoding="utf-8"), a.mode), encoding="utf-8")
    print(f"CIV1_RETARGET_AXIS_CANDIDATE_OK mode={a.mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
