from pathlib import Path

WITNESS = Path(__file__).parents[1] / "tools" / "godot_civ1_left_ground_reference_witness.gd"
MAIN_SCENE = Path(__file__).parents[1] / "game" / "main.tscn"


def test_left_ground_reference_witness_contract() -> None:
    source = WITNESS.read_text(encoding="utf-8")
    main_scene = MAIN_SCENE.read_text(encoding="utf-8")
    required = [
        'const MAIN_SCENE_PATH := "res://game/main.tscn"',
        'const MAIN_GROUND_PATH := NodePath("Ground")',
        'const TARGET_SAMPLES := [114, 115, 116, 117, 118, 119]',
        '"reference_semantic":"canonical_main_ground_collision_raycast"',
        '"ground_contact_claimed":false',
        '"reference_is_external_scene_ground":true',
        '"placement_semantic":"align_bilateral_cycle_lower_envelope_to_canonical_ground_top"',
        'PhysicsRayQueryParameters3D.create',
        'canonical_ground.use_collision',
        'mixamorig_Head',
        'max_pose_error>0.0001',
        'max_head_follow_error>0.0001',
        'root.size=Vector2i(WIDTH,HEIGHT)',
    ]
    for token in required:
        assert token in source, token
    canonical_ground_tokens = [
        '[node name="Ground" type="CSGBox3D" parent="."]',
        'position = Vector3(0, -0.23, 0)',
        'size = Vector3(1800, 0.4, 1800)',
        'use_collision = true',
    ]
    for token in canonical_ground_tokens:
        assert token in main_scene, token
    forbidden = [
        '"ground_contact_claimed":true',
        '"runtime_authorized":true',
        '"visual_approval_claimed":true',
        '"player_view_claimed":true',
        '"reference_semantic":"bilateral_cycle_lower_envelope_y"',
    ]
    for token in forbidden:
        assert token not in source, token


if __name__ == "__main__":
    test_left_ground_reference_witness_contract()
    print("CIV1_LEFT_GROUND_REFERENCE_WITNESS_CONTRACT_OK")
