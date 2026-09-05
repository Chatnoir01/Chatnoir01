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
        'const LEFT_SOLE_PROXY_LOCAL := Vector3(0.0, -0.012, 0.08)',
        '"sole_proxy_semantic":"left_foot_bone_oriented_kinematic_proxy_not_rendered_mesh"',
        '"rendered_sole_contact_claimed":false',
        '"reference_semantic":"canonical_main_ground_collision_raycast"',
        '"ground_contact_claimed":false',
        '"reference_is_external_scene_ground":true',
        'camera.position=Vector3(2.35,0.23+placement_y,0.0)',
        'camera.look_at(Vector3(0.0,0.16+placement_y,0.0))',
        '"camera_semantic":"low_side_contact_view_tracks_placement_y"',
        '"camera_tracks_placement_y":true',
        'PhysicsRayQueryParameters3D.create',
        'sole_proxy_ground_hit_y_m',
        'candidate_sole_proxy_horizontal_path_m',
        'candidate_sole_proxy_min_clearance_m',
        'candidate_sole_proxy_max_clearance_m',
        'canonical_ground.use_collision',
        'mixamorig_Head',
        'max_pose_error>0.0001',
        'max_head_follow_error>0.0001',
        'root.size=Vector2i(WIDTH,HEIGHT)',
    ]
    for token in required:
        assert token in source, token
    for token in [
        '[node name="Ground" type="CSGBox3D" parent="."]',
        'position = Vector3(0, -0.23, 0)',
        'size = Vector3(1800, 0.4, 1800)',
        'use_collision = true',
    ]:
        assert token in main_scene, token
    forbidden = [
        '"ground_contact_claimed":true',
        '"rendered_sole_contact_claimed":true',
        '"runtime_authorized":true',
        '"visual_approval_claimed":true',
        '"player_view_claimed":true',
        '"sole_proxy_semantic":"rendered_mesh_sole"',
        'camera.position=Vector3(0.0,0.95+placement_y,3.0)',
    ]
    for token in forbidden:
        assert token not in source, token


if __name__ == "__main__":
    test_left_ground_reference_witness_contract()
    print("CIV1_LEFT_GROUND_REFERENCE_WITNESS_CONTRACT_OK")
