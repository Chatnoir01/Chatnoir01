#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_right_foot_child_inventory_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-right-foot-child-inventory.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert PROBE.exists(), "RightFoot child inventory probe missing"
    assert WORKFLOW.exists(), "RightFoot child inventory workflow missing"
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    for token in (
        'SOURCE_SCENE_SUFFIX := "Models_with_rigging/Master_Rigged.tscn"',
        'TARGET_SCENE := "res://civ1_body.glb"',
        'RIGHT_FOOT_ALIASES := ["rightfoot", "rfoot"]',
        'LEFT_FOOT_ALIASES := ["leftfoot", "lfoot"]',
        "func _foot_index(skeleton: Skeleton3D, aliases: Array) -> int:",
        '"source_right_foot_direct_children"',
        '"target_right_foot_direct_children"',
        '"source_right_foot_descendants"',
        '"target_right_foot_descendants"',
        '"source_toe_like_descendants"',
        '"target_toe_like_descendants"',
        '"local_rest_origin"',
        '"global_rest_origin"',
        '"local_rest_basis_quat_xyzw"',
        '"global_rest_basis_quat_xyzw"',
        '"bilateral_rest_basis"',
        '"right_source_target_global_delta_deg"',
        '"left_source_target_global_delta_deg"',
        '"right_minus_left_global_delta_deg"',
        '"grand-bruxelles-civ1-right-foot-child-inventory-v2"',
        '"diagnostic_only": true',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
    ):
        require(probe, token)
    for token in (
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "right-foot-child-inventory.json",
        "source_toe_like_descendants",
        "target_toe_like_descendants",
        "bilateral_rest_basis",
        "right_minus_left_global_delta_deg",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(workflow, token)
    print("CIV1_RIGHT_FOOT_CHILD_INVENTORY_CONTRACT_OK")


if __name__ == "__main__":
    main()
