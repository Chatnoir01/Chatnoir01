from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-upperleg-lowerleg-rest-rotation-decomposition.yml"
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_upperleg_lowerleg_rest_rotation_probe.gd"


def test_upperleg_lowerleg_rest_rotation_contract() -> None:
    assert WORKFLOW.exists(), "missing UpperLeg->LowerLeg rest/rotation workflow"
    assert PROBE.exists(), "missing UpperLeg->LowerLeg rest/rotation Godot probe"

    workflow = WORKFLOW.read_text()
    probe = PROBE.read_text()

    required_workflow = [
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "SAMPLE_COUNT = 121",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "PRIMARY_SOURCE_WINDOW = range(58, 69)",
        "SUPPORT_BAND_FRACTION = 0.10",
        "common_mirrored_target_rest_cf_y_mae_m",
        "source_parent_rotation_cf_y_mae_m",
        "parent_rotation_delta_angle_mae_rad",
        "parent_rotation_delta_euler_abs_mae_rad",
        "bilateral_parent_rotation_delta_angle_mismatch_rad",
        "full_cycle_phase",
        "support_window",
        "candidate_promising",
        "upperleg_lowerleg_rest_rotation",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ]
    for token in required_workflow:
        assert token in workflow, f"workflow missing {token}"

    required_probe = [
        '"LeftUpperLeg"',
        '"LeftLowerLeg"',
        '"RightUpperLeg"',
        '"RightLowerLeg"',
        "RetargetModifier3D",
        "set_use_global_pose(false)",
        "set_position_enabled(false)",
        "set_rotation_enabled(true)",
        "set_scale_enabled(false)",
        "common_parent_rest_basis",
        "common_mirrored_target_rest_counterfactual",
        "rotated_target_rest_vector",
        "source_rest_direction_counterfactual",
        "source_parent_rotation_counterfactual",
        "parent_rotation_delta_angle_rad",
        "parent_rotation_delta_euler_rad",
        "local_translation_residual",
        "diagnostic_only",
        "world_ground_assumed",
        "runtime_authorized",
        "visual_approval_claimed",
    ]
    for token in required_probe:
        assert token in probe, f"probe missing {token}"
