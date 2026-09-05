from pathlib import Path

WITNESS = Path(__file__).parents[1] / "tools" / "godot_civ1_left_ground_reference_witness.gd"


def test_left_ground_reference_witness_contract() -> None:
    source = WITNESS.read_text(encoding="utf-8")
    required = [
        'const TARGET_SAMPLES := [114, 115, 116, 117, 118, 119]',
        '"reference_semantic":"bilateral_cycle_lower_envelope_y"',
        '"ground_contact_claimed":false',
        '"reference_is_external_scene_ground":false',
        '"target_left_candidate_samples":[115,116,117,118]',
        'PlaneMesh.new()',
        'mixamorig_Head',
        'max_pose_error > 0.0001 or max_head_follow_error > 0.0001',
        'root.size = Vector2i(WIDTH, HEIGHT)',
    ]
    for token in required:
        assert token in source, token
    forbidden = ['"ground_contact_claimed":true', '"reference_is_external_scene_ground":true', '"runtime_authorized":true', '"visual_approval_claimed":true', '"player_view_claimed":true']
    for token in forbidden:
        assert token not in source, token


if __name__ == "__main__":
    test_left_ground_reference_witness_contract()
    print("CIV1_LEFT_GROUND_REFERENCE_WITNESS_CONTRACT_OK")
