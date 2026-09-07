from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_bind_pose_probe.gd"
s = p.read_text()
required = [
    'const FOOT := "mixamorig_RightFoot"',
    'const TOE := "mixamorig_RightToeBase"',
    'const NORMALIZATION_TOLERANCE := 0.0001',
    'grand-bruxelles-civ1-rightfoot-bind-pose-basis-v1',
    'same_fixed_righttoebase_positive_vertex_population_from_validated_chain_geometry',
    'stored_weight_greater_than_zero_only',
    'skin.get_bind_pose(bind)',
    '"bind_index":bind',
    '"inverse_bind_transform":_transform_array(bind_pose)',
    '"mesh_to_skeleton_rest":_transform_array(mesh_to_skeleton_rest)',
    'vertices_with_complete_bind_space == 3306',
    'selected.size() == 3306',
    'if w <= 0.0: continue',
    'if not has_toe: continue',
    '"rigid_parent_proxy_authorized":false',
    '"global_pose_as_bind_matrix_authorized":false',
    '"skinned_replay_authorized":false',
    '"animation_correction_authorized":false',
    '"runtime_authorized":false',
    '"visual_approval_claimed":false',
    '"player_view_claimed":false',
]
for token in required:
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'bottom_percent', 'lowest_row', 'near_white',
    'camera_position', 'camera_fov', 'viewport_size', 'percentile',
):
    assert forbidden not in s, forbidden

collect = s[s.index('func _collect_mesh'):]
assert 'var bind := int(binds[idx])' in collect
assert 'var bone := _resolve_bind(skin, bind, skeleton, counters)' in collect
assert 'var bind_pose := skin.get_bind_pose(bind)' in collect
assert 'if not finite:' in collect
assert 'sum += w' in collect
assert 'if bone == toe:' in collect
assert 'has_toe = true' in collect
assert '>= 0.5' not in collect and '> 0.25' not in collect

# The bind pose is evidence only. This lot must not promote replay before the
# pose artifact and bind-pose artifact are joined and independently replayed.
assert '"skinned_replay_authorized":true' not in s
print('CIV1_RIGHTFOOT_BIND_POSE_CONTRACT_OK')
