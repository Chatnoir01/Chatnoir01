from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-bilateral-target-safe-foot-reference.yml"
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_bilateral_target_safe_foot_reference_probe.gd"


def test_bilateral_target_safe_foot_reference_contract():
    assert WORKFLOW.exists(), "missing bilateral target-safe Foot rest-reference workflow"
    assert PROBE.exists(), "missing dedicated bilateral target-safe Foot probe"

    workflow = WORKFLOW.read_text()
    probe = PROBE.read_text()

    for token in [
        "Grand Bruxelles CIV-1 Bilateral Target-Safe Foot Reference",
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "PRIMARY_SOURCE_WINDOW = range(58, 69)",
        "secondary_window_count",
        "source_phase_overlap_count",
        "support_plane_mae_m",
        "bilateral_non_regression",
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
        "target_local_rest_vector",
        "mirrored_common_direction",
        "target_safe_reference_vector",
        "get_bone_global_pose",
        '"source_actual_relative_vector"',
        '"baseline_actual_relative_vector"',
        '"target_safe_counterfactual_vector"',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ]:
        assert token in probe

    assert "set_position_enabled(false)" in probe
    assert "set_rotation_enabled(true)" in probe
    assert "set_scale_enabled(false)" in probe
