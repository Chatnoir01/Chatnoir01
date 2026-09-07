from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_skinned_replay.gd"
s = p.read_text()
required = [
    'const TARGET_SAMPLES := [68, 69, 70, 71]',
    'const REQUIRED_VERTEX_COUNT := 3306',
    'grand-bruxelles-civ1-rightfoot-skinned-replay-v1',
    'posed_bone_global * inverse_bind * mesh_to_skeleton_rest * source_vertex',
    'mixamorig_RightLeg":"RightLowerLeg',
    'mixamorig_RightFoot":"RightFoot',
    'mixamorig_RightToeBase":"RightToeBase',
    'stable_replay_sample_count >= 3',
    'func _sample_indices_match(value: Variant) -> bool:',
    'if int(value[i]) != int(TARGET_SAMPLES[i]):',
    '"quantitative_foot_slide_candidate":false',
    '"animation_correction_authorized":false',
    '"runtime_authorized":false',
    '"visual_approval_claimed":false',
    '"player_view_claimed":false',
]
for token in required:
    assert token in s, token
for forbidden in (
    'WEIGHT_THRESHOLD', 'percentile', 'bottom_percent', 'lowest_row',
    'camera_position', 'camera_fov', 'viewport_size',
    'rigid_parent_proxy', 'global_pose_as_bind_matrix',
    'toe_pose.get("sample_indices", []) != TARGET_SAMPLES',
    '"quantitative_foot_slide_candidate":true',
    '"animation_correction_authorized":true',
    '"runtime_authorized":true',
):
    assert forbidden not in s, forbidden
assert 'accum += (posed_bone * inverse_bind * p_skeleton_rest) * w' in s
assert 'abs(weight_sum - 1.0) > WEIGHT_SUM_TOLERANCE' in s
assert 'replayed.size() == REQUIRED_VERTEX_COUNT' in s
print('CIV1_RIGHTFOOT_SKINNED_REPLAY_CONTRACT_OK')
