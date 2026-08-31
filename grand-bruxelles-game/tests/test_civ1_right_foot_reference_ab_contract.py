#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_right_foot_reference_ab_probe.gd"
BASELINE_PROBE = ROOT / "tools" / "godot_civ1_native_retarget_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-right-foot-reference-ab.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert BASELINE_PROBE.exists(), "baseline native retarget probe missing"
    assert PROBE.exists(), "RightFoot reference A/B probe missing"
    assert WORKFLOW.exists(), "RightFoot reference A/B workflow missing"
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "SAMPLE_COUNT := 121",
        "SUPPORT_BAND_FRACTION := 0.10",
        "MIN_FOOT_RANGE_M := 0.05",
        "RetargetModifier3D.new()",
        "set_use_global_pose(false)",
        "set_position_enabled(false)",
        "set_rotation_enabled(true)",
        "set_scale_enabled(false)",
        "source_reference_direction_global",
        "target_right_foot_original_local_rest_origin",
        "target_right_foot_normalized_local_rest_origin",
        "target_right_foot_length_preserved",
        "set_bone_rest(target_right_idx, normalized_right_foot_rest)",
        '"grand-bruxelles-civ1-right-foot-reference-ab-v1"',
        '"reference_normalization_applied": true',
        '"counterfactual_only": false',
        '"diagnostic_only": true',
        '"run_alias_selected": false',
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
        "gb_civ1_native_retarget.gd",
        "gb_civ1_right_foot_reference_ab.gd",
        "baseline-native.json",
        "normalized-right-foot.json",
        "target_right_foot_length_preserved",
        "normalized_right_median_improves_baseline",
        "normalized_right_p90_improves_baseline",
        "assert right_median_improved is True",
        "assert right_p90_improved is True",
        "assert p['sample_count']==121",
        "assert p['support_band_fraction']==0.10",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(workflow, token)

    print("CIV1_RIGHT_FOOT_REFERENCE_AB_CONTRACT_OK")


if __name__ == "__main__":
    main()
