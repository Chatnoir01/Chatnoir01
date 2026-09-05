from pathlib import Path

WITNESS = Path(__file__).parents[1] / "tools" / "godot_civ1_dynamic_full_character_witness.gd"


def test_dynamic_full_character_witness_contract() -> None:
    source = WITNESS.read_text(encoding="utf-8")
    required = [
        'const BODY_PATH := "res://civ1_body.glb"',
        'const HEAD_PATH := "res://vitruvian_head.glb"',
        'const HEAD_BONE := "mixamorig_Head"',
        'frames.size() != 120',
        'BoneAttachment3D.new()',
        'head_rig.global_transform = Transform3D.IDENTITY',
        'func _head_expected_world(',
        'var max_pose_error := _apply_frame(skeleton, mapping, frames[0])',
        'await process_frame\n    await process_frame',
        'settled_expected_head_world.affine_inverse() * attachment.global_transform',
        'var predicted_attachment_world := expected_head_world * head_follow_calibration',
        'attachment.global_transform.origin.distance_to(predicted_attachment_world.origin)',
        '"head_follow_metric": "settled_calibrated_bone_attachment_world_residual"',
        '"head_attachment_calibration_offset_m": head_attachment_calibration_offset_m',
        '"head_settle_frames": 2',
        '_support_band_path(frames, "RightFoot")',
        '_support_band_path(frames, "LeftFoot")',
        'pelvis_vertical_range_m',
        'max_knee_correction_m',
        '"runtime_authorized": false',
        '"visual_approval_claimed": false',
        '"player_view_claimed": false',
        '"verdict": "REQUIRE_HUMAN_DYNAMIC_VISUAL_REVIEW"',
        'max_pose_error > 0.0001 or max_head_follow_error > 0.0001',
        '"JETER_DYNAMIC_TECHNICAL_DRIFT"',
        'root.size = Vector2i(WIDTH, HEIGHT)',
        'var lo: float = float(ys.min())',
        'var hi: float = float(ys.max())',
        'var knee_corr: float = max(',
    ]
    for token in required:
        assert token in source, token

    forbidden = [
        'var lo := ys.min()',
        'var hi := ys.max()',
        'var knee_corr := max(',
        'attachment.global_transform.origin.distance_to(expected_head_origin)',
        'expected_head_world.affine_inverse() * attachment.global_transform\n            head_attachment_calibration_offset_m',
    ]
    for token in forbidden:
        assert token not in source, token

    assert 'runtime_authorized": true' not in source
    assert 'visual_approval_claimed": true' not in source
    assert 'player_view_claimed": true' not in source
    assert source.count("await _capture(") == 1


if __name__ == "__main__":
    test_dynamic_full_character_witness_contract()
    print("CIV1_DYNAMIC_FULL_CHARACTER_WITNESS_CONTRACT_OK")
