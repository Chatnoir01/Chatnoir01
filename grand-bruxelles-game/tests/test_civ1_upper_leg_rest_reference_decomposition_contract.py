#!/usr/bin/env python3
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = GAME_ROOT.parent
WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-civ1-upper-leg-rest-reference-decomposition.yml"
GLOBAL_PROBE = GAME_ROOT / "tools/godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert WORKFLOW.is_file(), "missing bilateral UpperLeg rest/reference decomposition workflow"
    assert GLOBAL_PROBE.is_file(), "missing global-chain diagnostic probe"
    w = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "RightUpperLeg",
        "LeftUpperLeg",
        "RightLowerLeg",
        "LeftLowerLeg",
        "RightFoot",
        "LeftFoot",
        "source_hips_relative_origin",
        "target_hips_relative_origin",
        "source_rest_origin",
        "target_rest_origin",
        "right_static_rest_offset_m",
        "left_static_rest_offset_m",
        "right_dynamic_residual_mae_m",
        "left_dynamic_residual_mae_m",
        "right_source_rest_counterfactual",
        "left_source_rest_counterfactual",
        "bilateral_asymmetry_m",
        "right_downstream_compensation_mean_m",
        "left_downstream_compensation_mean_m",
        "downstream_compensation_bilateral_delta_m",
        "right_lowerleg_relative_error_mean_m",
        "left_lowerleg_relative_error_mean_m",
        "right_foot_relative_error_mean_m",
        "left_foot_relative_error_mean_m",
        "common_mode_upper_leg_offset",
        "downstream_compensation_asymmetry_dominant",
        "rest_offset_dominant",
        "rotation_or_dynamic_trajectory_dominant",
        "threshold_was_modified",
        "diagnostic_only",
        "world_ground_assumed",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(w, token)

    for token in ("threshold_rescue", "camera_rescue", "runtime_authorized=true", "world_ground_assumed=true"):
        assert token not in w.lower(), f"forbidden rescue/authority token: {token}"

    print("CIV1_UPPER_LEG_REST_REFERENCE_DECOMPOSITION_CONTRACT_OK")


if __name__ == "__main__":
    main()
