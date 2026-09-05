#!/usr/bin/env python3
"""Fail-closed validator for CIV-1 sole-proxy diagnostic receipts.

This validator deliberately does not promote a kinematic proxy into rendered-sole,
ground-contact, visual-approval, player-view, or runtime authorization evidence.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-civ1-left-ground-reference-v3"
EXPECTED_SAMPLES = [114, 115, 116, 117, 118, 119]
EXPECTED_CANDIDATE = [115, 116, 117, 118]
EXPECTED_COLLIDER = "CanonicalMainGround"
FORBIDDEN_TRUE_FLAGS = (
    "ground_contact_claimed",
    "rendered_sole_contact_claimed",
    "runtime_authorized",
    "visual_approval_claimed",
    "player_view_claimed",
)


class ReceiptError(ValueError):
    pass


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ReceiptError(f"{field}: expected number")
    number = float(value)
    if not math.isfinite(number):
        raise ReceiptError(f"{field}: non-finite")
    return number


def validate_report(report: dict[str, Any]) -> dict[str, Any]:
    if report.get("schema") != EXPECTED_SCHEMA:
        raise ReceiptError("schema")
    if report.get("diagnostic_only") is not True:
        raise ReceiptError("diagnostic_only")
    if report.get("reference_is_external_scene_ground") is not True:
        raise ReceiptError("reference_is_external_scene_ground")
    if report.get("reference_semantic") != "canonical_main_ground_collision_raycast":
        raise ReceiptError("reference_semantic")
    if report.get("sole_proxy_semantic") != "left_foot_bone_oriented_kinematic_proxy_not_rendered_mesh":
        raise ReceiptError("sole_proxy_semantic")

    for flag in FORBIDDEN_TRUE_FLAGS:
        if report.get(flag) is not False:
            raise ReceiptError(flag)

    if report.get("context_samples") != EXPECTED_SAMPLES:
        raise ReceiptError("context_samples")
    if report.get("target_left_candidate_samples") != EXPECTED_CANDIDATE:
        raise ReceiptError("target_left_candidate_samples")
    if report.get("resolution") != [1280, 720]:
        raise ReceiptError("resolution")

    for field in (
        "candidate_left_horizontal_path_m",
        "candidate_sole_proxy_horizontal_path_m",
        "candidate_left_min_clearance_m",
        "candidate_left_max_clearance_m",
        "candidate_sole_proxy_min_clearance_m",
        "candidate_sole_proxy_max_clearance_m",
        "max_pose_origin_error_m",
        "max_head_follow_error_m",
    ):
        value = _finite_number(report.get(field), field)
        if value < 0.0:
            raise ReceiptError(f"{field}: negative")

    if _finite_number(report["max_pose_origin_error_m"], "max_pose_origin_error_m") > 0.0001:
        raise ReceiptError("max_pose_origin_error_m: rail")
    if _finite_number(report["max_head_follow_error_m"], "max_head_follow_error_m") > 0.0001:
        raise ReceiptError("max_head_follow_error_m: rail")

    samples = report.get("samples")
    if not isinstance(samples, list) or [sample.get("sample_index") for sample in samples] != EXPECTED_SAMPLES:
        raise ReceiptError("samples")
    for sample in samples:
        for collider_field in ("left_collider_name", "right_collider_name", "sole_proxy_collider_name"):
            if sample.get(collider_field) != EXPECTED_COLLIDER:
                raise ReceiptError(f"sample {sample.get('sample_index')} {collider_field}")
        for clearance_field in ("left_clearance_m", "right_clearance_m", "sole_proxy_clearance_m"):
            if _finite_number(sample.get(clearance_field), clearance_field) < 0.0:
                raise ReceiptError(f"sample {sample.get('sample_index')} {clearance_field}: below ground")

    captures = report.get("captures")
    if not isinstance(captures, list) or [capture.get("sample_index") for capture in captures] != EXPECTED_SAMPLES:
        raise ReceiptError("captures")
    if any(capture.get("view") != "low_side_contact" for capture in captures):
        raise ReceiptError("capture view")

    return {
        "schema": "grand-bruxelles-civ1-sole-proxy-validation-v1",
        "source_schema": EXPECTED_SCHEMA,
        "valid": True,
        "diagnostic_only": True,
        "rendered_sole_contact_claimed": False,
        "ground_contact_claimed": False,
        "runtime_authorized": False,
        "verdict": "AMELIORER_PROXY_RECEIPT_VALID_RENDERED_SOLE_UNPROVEN",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_civ1_sole_proxy_report.py REPORT.json", file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(report, dict):
            raise ReceiptError("root")
        result = validate_report(report)
    except (OSError, json.JSONDecodeError, ReceiptError) as exc:
        print(f"CIV1_SOLE_PROXY_REPORT_INVALID: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    print("CIV1_SOLE_PROXY_REPORT_VALID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
