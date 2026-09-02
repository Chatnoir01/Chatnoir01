#!/usr/bin/env python3
"""Classify CIV-1 bilateral foot rest-direction evidence without authorizing runtime changes.

RightFoot must demonstrate the measured material->non-material causal improvement, while
LeftFoot acts as a symmetric non-material control. Mere presence of two counterfactual
objects is never sufficient for a QA allow verdict.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

SIDES = ("LeftFoot", "RightFoot")
CONTROL_TOLERANCE_SAMPLES = 1


def _counterfactual(payload: dict, foot: str) -> dict | None:
    key = "left_foot_reference_ab" if foot == "LeftFoot" else "right_foot_reference_ab"
    value = payload.get(key)
    return value if isinstance(value, dict) else None


def assess(payload: dict) -> dict:
    failures: list[str] = []
    phase = payload.get("phase_vertical_summary", {})
    threshold = phase.get("material_threshold_samples")
    per_bone = phase.get("per_bone", {})
    if not isinstance(threshold, int):
        failures.append("missing_material_threshold")
    if not isinstance(per_bone, dict):
        failures.append("missing_phase_inventory")
        per_bone = {}

    feet: dict[str, dict] = {}
    for foot in SIDES:
        baseline = per_bone.get(foot)
        if not isinstance(baseline, dict):
            failures.append(f"missing_baseline:{foot}")
            continue
        try:
            baseline_delta = int(baseline["phase_delta_samples"])
            baseline_material = bool(baseline["material_phase_divergence"])
        except (KeyError, TypeError, ValueError):
            failures.append(f"invalid_baseline:{foot}")
            continue

        cf = _counterfactual(payload, foot)
        row = {
            "baseline_phase_delta_samples": baseline_delta,
            "baseline_material_phase_divergence": baseline_material,
            "counterfactual_present": cf is not None,
            "rest_direction_causality_supported": False,
            "non_material_control_stable": False,
        }
        if cf is not None:
            required = (
                "baseline_phase_delta_samples",
                "normalized_phase_delta_samples",
                "target_foot_length_preserved",
                "normalization_improves_phase",
                "normalization_reaches_non_material_phase",
                "counterfactual_only",
            )
            missing = [key for key in required if key not in cf]
            if missing:
                failures.append(f"incomplete_counterfactual:{foot}:{','.join(missing)}")
            else:
                try:
                    cf_baseline = int(cf["baseline_phase_delta_samples"])
                    normalized = int(cf["normalized_phase_delta_samples"])
                except (TypeError, ValueError):
                    failures.append(f"invalid_counterfactual_phase:{foot}")
                    feet[foot] = row
                    continue
                if cf_baseline != baseline_delta:
                    failures.append(f"baseline_counterfactual_mismatch:{foot}")
                length_preserved = bool(cf["target_foot_length_preserved"])
                counterfactual_only = bool(cf["counterfactual_only"])
                reaches_non_material = bool(cf["normalization_reaches_non_material_phase"])
                if not length_preserved:
                    failures.append(f"foot_length_not_preserved:{foot}")
                if not counterfactual_only:
                    failures.append(f"counterfactual_contract_missing:{foot}")
                row["normalized_phase_delta_samples"] = normalized
                if baseline_material:
                    row["rest_direction_causality_supported"] = (
                        bool(cf["normalization_improves_phase"])
                        and reaches_non_material
                        and length_preserved
                        and counterfactual_only
                    )
                else:
                    control_stable = (
                        abs(normalized) <= abs(baseline_delta) + CONTROL_TOLERANCE_SAMPLES
                        and reaches_non_material
                        and length_preserved
                        and counterfactual_only
                    )
                    row["non_material_control_stable"] = control_stable
                    if not control_stable:
                        failures.append(f"non_material_control_drift:{foot}")
        feet[foot] = row

    bilateral_complete = all(feet.get(foot, {}).get("counterfactual_present", False) for foot in SIDES)
    right_cause = feet.get("RightFoot", {}).get("rest_direction_causality_supported", False)
    left_control = feet.get("LeftFoot", {}).get("non_material_control_stable", False)

    if failures:
        verdict = "BLOCK_INVALID_REST_EVIDENCE"
    elif not bilateral_complete:
        verdict = "BLOCK_INCOMPLETE_BILATERAL_REST_EVIDENCE"
    elif not right_cause or not left_control:
        verdict = "BLOCK_UNSUPPORTED_BILATERAL_REST_ATTRIBUTION"
    else:
        verdict = "ALLOW_QA_BILATERAL_REST_ATTRIBUTION"

    return {
        "format": "grand-bruxelles-civ1-bilateral-rest-causality-v2",
        "bilateral_counterfactual_complete": bilateral_complete,
        "right_rest_direction_causality_supported": right_cause,
        "left_non_material_control_stable": left_control,
        "control_tolerance_samples": CONTROL_TOLERANCE_SAMPLES,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "feet": feet,
        "failures": failures,
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("diagnostic", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-verdict")
    args = parser.parse_args()
    payload = json.loads(args.diagnostic.read_text(encoding="utf-8"))
    result = assess(payload)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(result["verdict"])
    if args.expect_verdict is not None:
        return 0 if result["verdict"] == args.expect_verdict else 1
    return 0 if result["verdict"] == "ALLOW_QA_BILATERAL_REST_ATTRIBUTION" else 1


if __name__ == "__main__":
    raise SystemExit(main())
