#!/usr/bin/env python3
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-foot-rotation-transition-v1"
REQUIRED_WINDOW = (78, 79)


def _quat(sample: dict, bone: str, side: str) -> tuple[float, float, float, float]:
    value = sample["bones"][bone][side]["model_rotation_xyzw"]
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError(f"invalid {bone} {side} quaternion")
    q = tuple(float(x) for x in value)
    if not all(math.isfinite(x) for x in q):
        raise ValueError("non-finite quaternion")
    norm = math.sqrt(sum(x * x for x in q))
    if norm < 1e-12:
        raise ValueError("degenerate quaternion")
    return tuple(x / norm for x in q)


def _conjugate(q):
    x, y, z, w = q
    return (-x, -y, -z, w)


def _multiply(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def _canonical(q):
    return tuple(-x for x in q) if q[3] < 0.0 else q


def _relative(a, b):
    return _canonical(_multiply(a, _conjugate(b)))


def _axis_angle(q):
    q = _canonical(q)
    x, y, z, w = q
    w = max(-1.0, min(1.0, w))
    angle = 2.0 * math.acos(w)
    scale = math.sqrt(max(0.0, 1.0 - w * w))
    axis = (1.0, 0.0, 0.0) if scale < 1e-10 else (x / scale, y / scale, z / scale)
    return {"angle_rad": angle, "angle_deg": math.degrees(angle), "axis_xyz": list(axis)}


def _bone_result(before: dict, after: dict, bone: str) -> dict:
    source_78 = _quat(before, bone, "source")
    source_79 = _quat(after, bone, "source")
    target_78 = _quat(before, bone, "target")
    target_79 = _quat(after, bone, "target")
    error_78 = _relative(target_78, source_78)
    error_79 = _relative(target_79, source_79)
    error_delta = _relative(error_79, error_78)
    return {
        "sample_78_target_vs_source": {"quaternion_xyzw": list(error_78), **_axis_angle(error_78)},
        "sample_79_target_vs_source": {"quaternion_xyzw": list(error_79), **_axis_angle(error_79)},
        "target_vs_source_error_delta_78_to_79": {"quaternion_xyzw": list(error_delta), **_axis_angle(error_delta)},
        "source_step_78_to_79": _axis_angle(_relative(source_79, source_78)),
        "target_step_78_to_79": _axis_angle(_relative(target_79, target_78)),
    }


def analyze(payload: dict, start: int = 78, end: int = 79) -> dict:
    if (start, end) != REQUIRED_WINDOW:
        raise ValueError("unsupported transition window")
    if payload.get("rotation_enabled") is not True:
        raise ValueError("rotation-enabled probe required")
    if payload.get("position_enabled") is not False or payload.get("scale_enabled") is not False:
        raise ValueError("position/scale-disabled probe required")
    samples = payload.get("model_space_samples")
    if not isinstance(samples, list) or len(samples) <= end:
        raise ValueError("insufficient model_space_samples")
    before, after = samples[start], samples[end]
    if before.get("sample_index") != start or after.get("sample_index") != end:
        raise ValueError("sample index drift")
    right = _bone_result(before, after, "RightFoot")
    left = _bone_result(before, after, "LeftFoot")
    right_delta = right["target_vs_source_error_delta_78_to_79"]["angle_deg"]
    left_delta = left["target_vs_source_error_delta_78_to_79"]["angle_deg"]
    return {
        "schema": SCHEMA,
        "diagnostic_only": True,
        "window": [start, end],
        "right_foot": right,
        "left_foot_control": left,
        "right_minus_left_error_delta_angle_deg": right_delta - left_delta,
        "runtime_authorized": False,
        "grounding_verified": False,
        "foot_slide_verified": False,
        "visual_approval_claimed": False,
        "verdict": "DIAGNOSTIC_FOOT_ROTATION_TRANSITION_ISOLATED",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("native_json")
    parser.add_argument("output_json")
    args = parser.parse_args()
    result = analyze(json.loads(Path(args.native_json).read_text()))
    Path(args.output_json).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    right = result["right_foot"]["target_vs_source_error_delta_78_to_79"]
    left = result["left_foot_control"]["target_vs_source_error_delta_78_to_79"]
    axis = right["axis_xyz"]
    print(
        "CIV1_FOOT_ROTATION_TRANSITION_OK "
        f"right_delta_deg={right['angle_deg']:.6f} "
        f"left_delta_deg={left['angle_deg']:.6f} "
        f"right_axis=({axis[0]:.6f},{axis[1]:.6f},{axis[2]:.6f})"
    )


if __name__ == "__main__":
    main()
