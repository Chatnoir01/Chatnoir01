#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "assess_civ1_shadow_parity.py"
spec = importlib.util.spec_from_file_location("shadow_parity", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def payload() -> dict:
    per_bone = {
        "RightFoot": {"source_vertical_min_sample_index": 59, "target_vertical_min_sample_index": 86, "phase_delta_samples": 27, "phase_delta_seconds": 0.15, "material_phase_divergence": True},
        "RightLowerLeg": {"source_vertical_min_sample_index": 3, "target_vertical_min_sample_index": 2, "phase_delta_samples": -1, "phase_delta_seconds": -0.0055, "material_phase_divergence": False},
    }
    return {
        "format": "grand-bruxelles-civ1-global-chain-diagnostic-v3",
        "source_animation": "UAL1_Standard/Sprint",
        "sample_count": 121,
        "retarget_modifier": "RetargetModifier3D",
        "use_global_pose": False,
        "position_enabled": False,
        "rotation_enabled": True,
        "scale_enabled": False,
        "diagnostic_bones": ["RightLowerLeg", "RightFoot"],
        "first_material_divergence_joint": "RightFoot",
        "right_foot_reference_ab": {"baseline_phase_delta_samples": 27, "normalized_phase_delta_samples": 0},
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "phase_vertical_summary": {"material_threshold_samples": 12, "first_material_divergence_joint": "RightFoot", "per_bone": per_bone},
    }


def main() -> int:
    base = payload()
    shadow = payload()
    shadow["phase_vertical_summary"]["per_bone"]["RightLowerLeg"]["source_vertical_min_sample_index"] = 2
    shadow["phase_vertical_summary"]["per_bone"]["RightLowerLeg"]["phase_delta_samples"] = 0
    result = module.assess(base, shadow)
    assert result["semantic_parity_verified"] is True

    bad = payload()
    bad["phase_vertical_summary"]["per_bone"]["RightFoot"]["material_phase_divergence"] = False
    assert "material_class_mismatch:RightFoot" in module.assess(base, bad)["failures"]

    bad = payload()
    bad["phase_vertical_summary"]["per_bone"]["RightLowerLeg"]["source_vertical_min_sample_index"] = 1
    assert any(item.startswith("phase_jitter_exceeded:RightLowerLeg") for item in module.assess(base, bad)["failures"])

    bad = payload()
    bad["right_foot_reference_ab"]["normalized_phase_delta_samples"] = 1
    assert "top_level_mismatch:right_foot_reference_ab" in module.assess(base, bad)["failures"]

    print("CIV1_SHADOW_PARITY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
