from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-lowerleg-foot-rest-rotation-decomposition.yml"
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_lowerleg_foot_rest_rotation_probe.gd"


def test_lowerleg_foot_rest_rotation_decomposition_contract():
    assert WORKFLOW.exists(), "missing bilateral LowerLeg->Foot rest/rotation decomposition workflow"
    assert PROBE.exists(), "missing dedicated Godot rest/rotation probe"

    workflow = WORKFLOW.read_text()
    probe = PROBE.read_text()

    for token in [
        "Grand Bruxelles CIV-1 LowerLeg Foot Rest Rotation Decomposition",
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "rotated_static_rest_error_m",
        "local_translation_residual_m",
        "rest_vector_bilateral_delta_m",
        "rotation_driven_bilateral_delta_m",
        "local_residual_bilateral_delta_m",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ]:
        assert token in workflow

    for token in [
        'const SAMPLE_COUNT := 121',
        '"LeftLowerLeg"',
        '"LeftFoot"',
        '"RightLowerLeg"',
        '"RightFoot"',
        "get_bone_rest",
        "get_bone_global_rest",
        "get_bone_global_pose",
        "parent_pose.basis * foot_local_rest.origin",
        '"rotated_static_rest_vector"',
        '"actual_relative_vector"',
        '"local_translation_residual"',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ]:
        assert token in probe

    assert "set_position_enabled(false)" in probe
    assert "set_rotation_enabled(true)" in probe
    assert "set_scale_enabled(false)" in probe
