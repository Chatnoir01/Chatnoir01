#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_native_retarget_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-native-retarget.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert PROBE.exists(), "native RetargetModifier3D probe missing"
    assert WORKFLOW.exists(), "native retarget workflow missing"

    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "RetargetModifier3D.new()",
        "set_use_global_pose(false)",
        "set_position_enabled(false)",
        "set_rotation_enabled(true)",
        "set_scale_enabled(false)",
        "SkeletonProfile.new()",
        '"grand-bruxelles-civ1-native-retarget-v1"',
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
        "target_left_support_candidate",
        "target_right_support_candidate",
        "native_support_improves_manual_baseline",
        "assert improved is True",
    ):
        require(workflow, token)

    print("CIV1_NATIVE_RETARGET_CONTRACT_OK")


if __name__ == "__main__":
    main()
