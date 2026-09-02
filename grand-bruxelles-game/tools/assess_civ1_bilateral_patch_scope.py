#!/usr/bin/env python3
"""Fail-closed scope assessment for CIV-1 downstream phase diagnostics.

Consumes the QA-only output of analyze_civ1_downstream_phase_transition.py.
It does not edit assets, retarget settings, animation data, thresholds, runtime,
or JOUABLE state. Its purpose is to prevent a unilateral leg/foot candidate from
being treated as justified when bilateral evidence is incomplete or the same
downstream component is implicated on both sides.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

EXPECTED_FORMAT = "grand-bruxelles-civ1-downstream-phase-transition-v2"
ALLOWED_SCOPES = ("right_only", "left_only", "bilateral", "shared")
DRIVER_TO_TERM = {
    "foot_relative": "foot_relative_m",
    "lowerleg_relative": "lowerleg_relative_m",
}


def _finite_cross(side: dict[str, Any], term: str) -> float | None:
    crossing = side.get("first_zero_cross_by_term", {}).get(term)
    if crossing is None:
        return None
    value = crossing.get("interpolated_index")
    if value is None:
        return None
    value = float(value)
    if not math.isfinite(value):
        raise ValueError(f"non-finite {term} crossing")
    return value


def _driver(side: dict[str, Any]) -> str | None:
    driver = side.get("downstream_cross_driver")
    if driver is None:
        return None
    value = driver.get("largest_absolute_delta_term")
    if value not in {"lowerleg_relative", "foot_relative", "tie"}:
        raise ValueError(f"unexpected downstream driver: {value!r}")
    return value


def _driver_cross(side: dict[str, Any], driver: str | None) -> float | None:
    if driver is None or driver == "tie":
        return None
    return _finite_cross(side, DRIVER_TO_TERM[driver])


def assess(payload: dict[str, Any], candidate_scope: str) -> dict[str, Any]:
    if candidate_scope not in ALLOWED_SCOPES:
        raise ValueError(f"unsupported candidate scope: {candidate_scope}")
    if payload.get("format") != EXPECTED_FORMAT:
        raise ValueError("unexpected downstream phase payload format")
    if payload.get("diagnostic_only") is not True:
        raise ValueError("expected diagnostic_only=true")
    if payload.get("runtime_authorized") is not False:
        raise ValueError("runtime authorization must remain false")
    if payload.get("visual_approval_claimed") is not False:
        raise ValueError("visual approval must remain false")

    right = payload.get("right")
    left = payload.get("left_control")
    if not isinstance(right, dict) or not isinstance(left, dict):
        raise ValueError("bilateral side records are required")

    right_foot_cross = _finite_cross(right, "foot_relative_m")
    left_foot_cross = _finite_cross(left, "foot_relative_m")
    right_driver = _driver(right)
    left_driver = _driver(left)
    right_driver_cross = _driver_cross(right, right_driver)
    left_driver_cross = _driver_cross(left, left_driver)

    evidence_complete = (
        right_driver is not None
        and left_driver is not None
        and right_driver != "tie"
        and left_driver != "tie"
        and right_driver_cross is not None
        and left_driver_cross is not None
    )
    same_dominant_driver = evidence_complete and right_driver == left_driver
    bilateral_foot_implication = (
        evidence_complete
        and right_driver == "foot_relative"
        and left_driver == "foot_relative"
    )

    unilateral = candidate_scope in {"right_only", "left_only"}
    if unilateral and not evidence_complete:
        unilateral_scope_authorized = False
        scope_verdict = "BLOCK_INCOMPLETE_EVIDENCE"
        reason = "bilateral_driver_or_driver_crossing_missing"
    elif unilateral and same_dominant_driver:
        unilateral_scope_authorized = False
        scope_verdict = "BLOCK_UNILATERAL_SCOPE"
        reason = "same_dominant_downstream_driver_on_both_sides"
    else:
        unilateral_scope_authorized = True
        if evidence_complete:
            scope_verdict = "ALLOW_QA_SCOPE"
            reason = "scope_not_blocked_by_bilateral_driver"
        else:
            scope_verdict = "ALLOW_QA_SCOPE_INCOMPLETE_EVIDENCE"
            reason = "incomplete_evidence_diagnostic_only"

    phase_skew_samples = None
    if right_foot_cross is not None and left_foot_cross is not None:
        phase_skew_samples = left_foot_cross - right_foot_cross

    driver_phase_skew_samples = None
    if (
        evidence_complete
        and right_driver == left_driver
        and right_driver_cross is not None
        and left_driver_cross is not None
    ):
        driver_phase_skew_samples = left_driver_cross - right_driver_cross

    return {
        "format": "grand-bruxelles-civ1-bilateral-patch-scope-v3",
        "source_format": EXPECTED_FORMAT,
        "candidate_scope": candidate_scope,
        "right_downstream_driver": right_driver,
        "left_downstream_driver": left_driver,
        "right_driver_cross_interpolated_index": right_driver_cross,
        "left_driver_cross_interpolated_index": left_driver_cross,
        "driver_phase_skew_samples": driver_phase_skew_samples,
        "right_foot_cross_interpolated_index": right_foot_cross,
        "left_foot_cross_interpolated_index": left_foot_cross,
        "foot_phase_skew_samples": phase_skew_samples,
        "evidence_complete": evidence_complete,
        "same_dominant_downstream_driver": same_dominant_driver,
        "bilateral_foot_implication": bilateral_foot_implication,
        "unilateral_scope_authorized": unilateral_scope_authorized,
        "scope_verdict": scope_verdict,
        "reason": reason,
        "diagnostic_only": True,
        "grounding_verified": False,
        "foot_slide_verified": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_json", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--candidate-scope", choices=ALLOWED_SCOPES, required=True)
    args = parser.parse_args()

    payload = json.loads(args.input_json.read_text(encoding="utf-8"))
    result = assess(payload, args.candidate_scope)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    if not result["unilateral_scope_authorized"]:
        print("CIV1_BILATERAL_PATCH_SCOPE_BLOCKED")
        return 3
    print("CIV1_BILATERAL_PATCH_SCOPE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
