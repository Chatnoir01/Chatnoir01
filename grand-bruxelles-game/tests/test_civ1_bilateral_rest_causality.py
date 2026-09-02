#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "assess_civ1_bilateral_rest_causality.py"
spec = importlib.util.spec_from_file_location("bilateral_rest", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def payload() -> dict:
    return {
        "phase_vertical_summary": {
            "material_threshold_samples": 12,
            "per_bone": {
                "LeftFoot": {"phase_delta_samples": 0, "material_phase_divergence": False},
                "RightFoot": {"phase_delta_samples": 27, "material_phase_divergence": True},
            },
        },
        "right_foot_reference_ab": {
            "baseline_phase_delta_samples": 27,
            "normalized_phase_delta_samples": 0,
            "target_foot_length_preserved": True,
            "normalization_improves_phase": True,
            "normalization_reaches_non_material_phase": True,
            "counterfactual_only": True,
        },
    }


def left_control(normalized: int = 0) -> dict:
    return {
        "baseline_phase_delta_samples": 0,
        "normalized_phase_delta_samples": normalized,
        "target_foot_length_preserved": True,
        "normalization_improves_phase": False,
        "normalization_reaches_non_material_phase": True,
        "counterfactual_only": True,
    }


def complete_payload() -> dict:
    value = payload()
    value["left_foot_reference_ab"] = left_control()
    return value


def main() -> int:
    measured = module.assess(payload())
    assert measured["verdict"] == "BLOCK_INCOMPLETE_BILATERAL_REST_EVIDENCE"
    assert measured["right_rest_direction_causality_supported"] is True
    assert measured["feet"]["LeftFoot"]["counterfactual_present"] is False
    assert measured["runtime_authorized"] is False

    allowed = module.assess(complete_payload())
    assert allowed["verdict"] == "ALLOW_QA_BILATERAL_REST_ATTRIBUTION"
    assert allowed["bilateral_counterfactual_complete"] is True
    assert allowed["right_rest_direction_causality_supported"] is True
    assert allowed["left_non_material_control_stable"] is True
    assert allowed["runtime_authorized"] is False

    jitter = complete_payload()
    jitter["left_foot_reference_ab"] = left_control(1)
    assert module.assess(jitter)["verdict"] == "ALLOW_QA_BILATERAL_REST_ATTRIBUTION"

    no_right_cause = complete_payload()
    no_right_cause["right_foot_reference_ab"]["normalization_improves_phase"] = False
    blocked_cause = module.assess(no_right_cause)
    assert blocked_cause["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "improvement_flag_mismatch:RightFoot" in blocked_cause["failures"]

    left_drift = complete_payload()
    left_drift["left_foot_reference_ab"] = left_control(2)
    blocked_left = module.assess(left_drift)
    assert blocked_left["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "non_material_control_drift:LeftFoot" in blocked_left["failures"]

    drift = complete_payload()
    drift["right_foot_reference_ab"]["baseline_phase_delta_samples"] = 26
    blocked = module.assess(drift)
    assert blocked["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "baseline_counterfactual_mismatch:RightFoot" in blocked["failures"]

    length = complete_payload()
    length["right_foot_reference_ab"]["target_foot_length_preserved"] = False
    blocked_length = module.assess(length)
    assert blocked_length["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "foot_length_not_preserved:RightFoot" in blocked_length["failures"]

    fake_non_material = complete_payload()
    fake_non_material["right_foot_reference_ab"]["normalized_phase_delta_samples"] = 14
    fake_non_material["right_foot_reference_ab"]["normalization_reaches_non_material_phase"] = True
    blocked_fake_non_material = module.assess(fake_non_material)
    assert blocked_fake_non_material["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "non_material_flag_mismatch:RightFoot" in blocked_fake_non_material["failures"]
    assert blocked_fake_non_material["right_rest_direction_causality_supported"] is False

    fake_baseline_class = complete_payload()
    fake_baseline_class["phase_vertical_summary"]["per_bone"]["RightFoot"]["material_phase_divergence"] = False
    blocked_fake_baseline = module.assess(fake_baseline_class)
    assert blocked_fake_baseline["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "baseline_material_flag_mismatch:RightFoot" in blocked_fake_baseline["failures"]

    fake_improvement = complete_payload()
    fake_improvement["right_foot_reference_ab"]["normalized_phase_delta_samples"] = 27
    fake_improvement["right_foot_reference_ab"]["normalization_improves_phase"] = True
    fake_improvement["right_foot_reference_ab"]["normalization_reaches_non_material_phase"] = False
    blocked_fake_improvement = module.assess(fake_improvement)
    assert blocked_fake_improvement["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "improvement_flag_mismatch:RightFoot" in blocked_fake_improvement["failures"]

    print("CIV1_BILATERAL_REST_CAUSALITY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
