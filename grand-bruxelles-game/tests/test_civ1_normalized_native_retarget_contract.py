#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_right_foot_reference_ab_probe.gd"
BUILDER = ROOT / "tools" / "build_civ1_right_foot_grounded_candidate.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-normalized-native-retarget.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing normalized native retarget contract token: {token}"


def main() -> None:
    assert PROBE.exists(), "canonical RightFoot reference probe missing"
    assert BUILDER.exists(), "versioned selected Y-blend candidate builder missing"
    assert WORKFLOW.exists(), "normalized native retarget strict-comparator workflow missing"

    probe = PROBE.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        'SELECTED_ALPHA = 0.75',
        'alpha_literal = f"{SELECTED_ALPHA:.6f}"',
        'var blend_alpha := {alpha_literal}',
        'var full_y := normalized_local_direction.y * target_length',
        'var original_y := target_right_foot_original_local_rest_origin.y',
        'source_global_reference_direction_y_blend_preserve_target_length',
        'grand-bruxelles-civ1-right-foot-reference-ab-v4',
        'target_right_foot_y_blend_alpha',
        'candidate source drift: expected exactly one token',
    ):
        require(builder, token)

    for token in (
        '"grand-bruxelles-civ1-right-foot-reference-ab-v2"',
        '"reference_normalization_applied": true',
        '"pose_reset_applied": true',
        'target_skeleton.set_bone_rest(target_right_idx, normalized_right_foot_rest)',
        'target_skeleton.reset_bone_pose(target_right_idx)',
        'SAMPLE_COUNT := 121',
        'SUPPORT_BAND_FRACTION := 0.10',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ):
        require(probe, token)

    for token in (
        'Grand Bruxelles CIV-1 Normalized Native Retarget',
        'build_civ1_right_foot_grounded_candidate.py',
        'gb_civ1_grounded_candidate.gd',
        'Godot_v4.7.1-stable_linux.x86_64.zip',
        'c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba',
        'f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767',
        '8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888',
        'CIV1_RIGHT_FOOT_REFERENCE_AB_OK',
        "assert p['format']=='grand-bruxelles-civ1-right-foot-reference-ab-v4'",
        "assert p['reference_normalization_method']=='source_global_reference_direction_y_blend_preserve_target_length'",
        "assert abs(float(p['target_right_foot_y_blend_alpha'])-0.75) < 1e-9",
        "assert p['sample_count']==121",
        "assert p['support_band_fraction']==0.10",
        "assert p['target_right_foot_length_preserved'] is True",
        "assert p['pose_reset_applied'] is True",
        "manual_baseline_left_median_mps = 6.845175",
        "manual_baseline_left_p90_mps = 33.326307",
        "manual_baseline_right_median_mps = 6.812484",
        "manual_baseline_right_p90_mps = 36.403685",
        "assert strict_bilateral_improvement is True",
        "assert source_phase_overlap_improved is True",
        "assert primary_phase_center_improved is True",
        "assert p['diagnostic_only'] is True",
        "assert p['run_alias_selected'] is False",
        "assert p['grounding_verified'] is False",
        "assert p['foot_slide_verified'] is False",
        "assert p['runtime_authorized'] is False",
        "assert p['visual_approval_claimed'] is False",
    ):
        require(workflow, token)

    print("CIV1_NORMALIZED_NATIVE_RETARGET_CONTRACT_OK")


if __name__ == "__main__":
    main()
