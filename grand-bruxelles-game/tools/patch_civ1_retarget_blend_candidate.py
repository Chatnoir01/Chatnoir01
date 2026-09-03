#!/usr/bin/env python3
"""Build QA-only partial CIV-1 rest-direction counterfactuals from the validated bilateral shadow probe."""
from __future__ import annotations
import argparse
from pathlib import Path

RIGHT = "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
LEFT = "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
MARKER = "CIV1_RETARGET_BLEND_CANDIDATE"


def _blend_literal(value: float) -> str:
    if not (0.0 < value < 1.0):
        raise ValueError("blend must be strictly between 0 and 1; endpoints are baseline/full-rest controls")
    return format(value, ".17g")


def transform(text: str, blend: float) -> str:
    b = _blend_literal(blend)
    if MARKER in text:
        raise ValueError("input already contains a blend candidate")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    if text.count(RIGHT) != 1 or text.count(LEFT) != 1:
        raise ValueError("validated rest-direction anchors drifted")
    right = (
        f"    # {MARKER} blend={b}\n"
        f"    var right_candidate_blend: float = {b}\n"
        "    var right_candidate_direction := (target_local_rest_origin.normalized() * (1.0 - right_candidate_blend) + normalized_target_local_direction * right_candidate_blend).normalized()\n"
        "    var normalized_target_local_rest_origin := right_candidate_direction * target_local_rest_origin.length()\n"
    )
    left = (
        f"    var left_candidate_blend: float = {b}\n"
        "    var left_candidate_direction := (target_left_local_rest_origin.normalized() * (1.0 - left_candidate_blend) + normalized_target_left_local_direction * left_candidate_blend).normalized()\n"
        "    var normalized_target_left_local_rest_origin := left_candidate_direction * target_left_local_rest_origin.length()\n"
    )
    out = text.replace(RIGHT, right, 1).replace(LEFT, left, 1)
    if out.count(MARKER) != 1:
        raise ValueError("candidate marker insertion failed")
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("input", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--blend", type=float, required=True)
    a = p.parse_args()
    a.output.write_text(transform(a.input.read_text(encoding="utf-8"), a.blend), encoding="utf-8")
    print(f"CIV1_RETARGET_BLEND_CANDIDATE_OK blend={a.blend}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
