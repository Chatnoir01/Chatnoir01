from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
PROBE = ROOT / "tools" / "godot_civ1_rightfoot_same_sample_ground_witness.gd"
WORKFLOW = REPO / ".github" / "workflows" / "grand-bruxelles-civ1-rightfoot-same-sample-ground.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing required contract token: {token}"


def forbid(text: str, token: str) -> None:
    assert token not in text, f"forbidden rescue/claim token present: {token}"


def main() -> None:
    text = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    require(text, 'const MAIN_SCENE_PATH := "res://game/main.tscn"')
    require(text, 'const MAIN_GROUND_PATH := NodePath("Ground")')
    require(text, 'const MAIN_CAMERA_PATH := NodePath("Player/CameraPivot/SpringArm3D/Camera3D")')
    require(text, 'const MAIN_SPRING_ARM_PATH := NodePath("Player/CameraPivot/SpringArm3D")')
    require(text, 'const TARGET_SAMPLES := [68, 69, 70, 71]')
    require(text, 'var bundle: Variant = _read_json(_bundle_path)')
    require(text, 'var toe_receipt: Variant = _read_json(_toe_path)')
    require(text, 'var parsed: Variant = JSON.parse_string(file.get_as_text())')
    require(text, 'canonical_main.get_node_or_null(MAIN_GROUND_PATH) as CSGBox3D')
    require(text, 'canonical_main.get_node_or_null(MAIN_CAMERA_PATH) as Camera3D')
    require(text, 'canonical_main.get_node_or_null(MAIN_SPRING_ARM_PATH) as SpringArm3D')
    require(text, 'if not canonical_ground.use_collision or canonical_ground.rotation.length() > 1e-8:')
    require(text, '"ground_reference_ready": true')
    require(text, '"same_sample_ground_evidence": true')
    require(text, '"player_camera_provenance_present": true')
    require(text, '"capture_camera_semantic": "canonical_player_camera_optics_contact_diagnostic"')
    require(text, '"resolution": [WIDTH, HEIGHT]')
    require(text, '"planted_contact_claimed": false')
    require(text, '"quantitative_foot_slide_candidate": false')
    require(text, '"animation_correction_authorized": false')
    require(text, '"runtime_authorized": false')
    require(text, '"visual_approval_claimed": false')
    require(text, '"player_view_claimed": false')
    require(text, 'CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_OK')

    # Receipt validation must respect Godot float32 serialization while remaining exact on semantics.
    require(workflow, 'def close_scalar(actual, expected, tol=1e-6):')
    require(workflow, 'def close_vector(actual, expected, tol=1e-6):')
    require(workflow, "close_vector(receipt['ground_source_position_m'], [0.0, -0.23, 0.0])")
    require(workflow, "close_vector(receipt['ground_source_size_m'], [1800.0, 0.4, 1800.0])")
    require(workflow, "close_scalar(receipt['ground_top_y_m'], -0.03)")
    require(workflow, "close_scalar(receipt['player_spring_length_m'], 4.9)")
    forbid(workflow, "assert receipt['ground_source_position_m'] == [0.0, -0.23, 0.0]")
    forbid(workflow, "assert receipt['ground_source_size_m'] == [1800.0, 0.4, 1800.0]")

    # This gate must not invent a perceptual/contact threshold or camera rescue.
    for forbidden in (
        "WEIGHT_THRESHOLD",
        "percentile(",
        "quantile(",
        "CONTACT_THRESHOLD",
        "FOOT_SLIDE_THRESHOLD",
        "camera_rescue",
        "viewport_rescue",
        "fov_rescue",
    ):
        forbid(text, forbidden)

    # The new witness must remain diagnostic-only and must not mutate the canonical scene.
    forbid(text, "canonical_main.add_child")
    forbid(text, "set_bone_pose_")
    print("CIV1_RIGHTFOOT_SAME_SAMPLE_GROUND_CONTRACT_OK")


if __name__ == "__main__":
    main()
