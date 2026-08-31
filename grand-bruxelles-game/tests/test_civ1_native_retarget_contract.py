#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_native_retarget_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-native-retarget.yml"
CHAIN_PROBE = ROOT / "tools" / "godot_civ1_leg_chain_diagnostic.gd"
CHAIN_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-leg-chain-diagnostic.yml"
GLOBAL_PROBE = ROOT / "tools" / "godot_civ1_global_chain_diagnostic.gd"
GLOBAL_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-global-chain-diagnostic.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert PROBE.exists(), "native RetargetModifier3D probe missing"
    assert WORKFLOW.exists(), "native retarget workflow missing"
    assert CHAIN_PROBE.exists(), "bilateral leg-chain diagnostic probe missing"
    assert CHAIN_WORKFLOW.exists(), "bilateral leg-chain diagnostic workflow missing"
    assert GLOBAL_PROBE.exists(), "model-space chain diagnostic probe missing"
    assert GLOBAL_WORKFLOW.exists(), "model-space chain diagnostic workflow missing"

    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    chain_probe = CHAIN_PROBE.read_text(encoding="utf-8")
    chain_workflow = CHAIN_WORKFLOW.read_text(encoding="utf-8")
    global_probe = GLOBAL_PROBE.read_text(encoding="utf-8")
    global_workflow = GLOBAL_WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "RetargetModifier3D.new()",
        "target_skeleton.reparent(modifier, true)",
        "target_skeleton.get_parent() == modifier",
        "set_use_global_pose(false)",
        "set_position_enabled(false)",
        "set_rotation_enabled(true)",
        "set_scale_enabled(false)",
        "SkeletonProfile.new()",
        "MIN_FOOT_RANGE_M := 0.05",
        '"source_left_foot_range_m"',
        '"source_right_foot_range_m"',
        '"target_left_foot_range_m"',
        '"target_right_foot_range_m"',
        '"source_bilateral_motion_verified"',
        '"target_bilateral_motion_verified"',
        '"source_left_support_candidate"',
        '"source_right_support_candidate"',
        '"target_left_support_candidate"',
        '"target_right_support_candidate"',
        '"right_support_sample_ratio_target_over_source"',
        '"left_support_sample_ratio_target_over_source"',
        '"low_height_sample_indices"',
        '"low_height_sample_times_s"',
        '"low_height_segment_start_indices"',
        '"low_height_windows"',
        '"wraps_cycle"',
        '"grand-bruxelles-civ1-native-retarget-v3"',
        '"diagnostic_only": true',
        '"run_alias_selected": false',
        '"world_ground_assumed": false',
        '"grounding_verified": false',
        '"foot_slide_verified": false',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ):
        require(probe, token)

    for token in (
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "CIV1_NATIVE_RETARGET_OK",
        "source_left_support_candidate",
        "source_right_support_candidate",
        "target_left_support_candidate",
        "target_right_support_candidate",
        "right_support_sample_ratio_target_over_source",
        "left_support_sample_ratio_target_over_source",
        "target_bilateral_motion_verified",
        "source_bilateral_motion_verified",
        "target_left_foot_range_m",
        "target_right_foot_range_m",
        "low_height_sample_indices",
        "low_height_sample_times_s",
        "low_height_segment_start_indices",
        "low_height_windows",
        "assert improved is True",
    ):
        require(workflow, token)

    for token in (
        "RetargetModifier3D.new()",
        "SkeletonProfile.new()",
        "SAMPLE_COUNT := 121",
        '"grand-bruxelles-civ1-leg-chain-diagnostic-v1"',
        '"leg_chain_rest_diagnostics"',
        '"leg_chain_pose_diagnostics"',
        '"LeftUpperLeg"',
        '"LeftLowerLeg"',
        '"LeftFoot"',
        '"RightUpperLeg"',
        '"RightLowerLeg"',
        '"RightFoot"',
        '"rest_local_rotation_delta_deg"',
        '"pose_local_rotation_delta_deg"',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ):
        require(chain_probe, token)

    for token in (
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "CIV1_LEG_CHAIN_DIAGNOSTIC_OK",
        "leg_chain_rest_diagnostics",
        "leg_chain_pose_diagnostics",
        "rest_local_rotation_delta_deg",
        "pose_local_rotation_delta_deg",
        "REST_BILATERAL_DIFF_MAX_DEG = 1.0",
        "POSE_REPRO_ERROR_MAX_DEG = 0.05",
        "rest_bilateral_symmetry_passed",
        "pose_excursion_reproduction_passed",
        "right_rest_frame_materially_worse",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(chain_workflow, token)

    for token in (
        "RetargetModifier3D.new()",
        "target_skeleton.reparent(modifier, true)",
        "SAMPLE_COUNT := 121",
        '"grand-bruxelles-civ1-global-chain-diagnostic-v1"',
        '"model_space_samples"',
        '"source_motion_from_rest"',
        '"target_motion_from_rest"',
        '"source_hips_relative_origin"',
        '"target_hips_relative_origin"',
        '"LeftUpperLeg"',
        '"LeftLowerLeg"',
        '"LeftFoot"',
        '"RightUpperLeg"',
        '"RightLowerLeg"',
        '"RightFoot"',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ):
        require(global_probe, token)

    for token in (
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK",
        "grand-bruxelles-civ1-global-chain-diagnostic-v1",
        "model_space_samples",
        "source_motion_from_rest",
        "target_motion_from_rest",
        "source_hips_relative_origin",
        "target_hips_relative_origin",
        "sample_count']==121",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(global_workflow, token)

    print("CIV1_NATIVE_RETARGET_CONTRACT_OK")


if __name__ == "__main__":
    main()
