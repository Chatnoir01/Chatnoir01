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


def main() -> int:
    measured = module.assess(payload())
    assert measured["verdict"] == "BLOCK_INCOMPLETE_BILATERAL_REST_EVIDENCE"
    assert measured["right_rest_direction_causality_supported"] is True
    assert measured["feet"]["LeftFoot"]["counterfactual_present"] is False
    assert measured["runtime_authorized"] is False

    complete = payload()
    complete["left_foot_reference_ab"] = {
        "baseline_phase_delta_samples": 0,
        "normalized_phase_delta_samples": 0,
        "target_foot_length_preserved": True,
        "normalization_improves_phase": False,
        "normalization_reaches_non_material_phase": True,
        "counterfactual_only": True,
    }
    allowed = module.assess(complete)
    assert allowed["verdict"] == "ALLOW_QA_BILATERAL_REST_ATTRIBUTION"
    assert allowed["bilateral_counterfactual_complete"] is True
    assert allowed["runtime_authorized"] is False

    drift = payload()
    drift["right_foot_reference_ab"]["baseline_phase_delta_samples"] = 26
    blocked = module.assess(drift)
    assert blocked["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "baseline_counterfactual_mismatch:RightFoot" in blocked["failures"]

    length = payload()
    length["right_foot_reference_ab"]["target_foot_length_preserved"] = False
    blocked_length = module.assess(length)
    assert blocked_length["verdict"] == "BLOCK_INVALID_REST_EVIDENCE"
    assert "foot_length_not_preserved:RightFoot" in blocked_length["failures"]

    print("CIV1_BILATERAL_REST_CAUSALITY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
