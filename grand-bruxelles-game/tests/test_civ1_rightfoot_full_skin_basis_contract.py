from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_full_skin_basis_probe.gd"
s = p.read_text()
required = [
    'const FOOT := "mixamorig_RightFoot"',
    'const TOE := "mixamorig_RightToeBase"',
    'const NORMALIZATION_TOLERANCE := 0.0001',
    'grand-bruxelles-civ1-rightfoot-full-skin-basis-v2',
    'same_fixed_righttoebase_positive_vertex_population_from_validated_chain_geometry',
    'stored_weight_greater_than_zero_only',
    'skin.get_bind_bone(bind)',
    'skin.get_bind_name(bind)',
    'skeleton.find_bone(bind_name)',
    'skeleton.get_bone_parent(current)',
    '"influences":influences',
    '"influence_weight_sum":sum',
    'if not per_bone.has(toe): continue',
    'selected.size() != 3306',
    'influence_weight_sum_min',
    'influence_weight_sum_max',
    'influence_count_histogram',
    'normalization_violation_count',
    'abs(s - 1.0) > NORMALIZATION_TOLERANCE',
    'full_vertex_influence_basis_available":true',
    'full_vertex_influence_basis_integrity_ready":normalization_violation_count == 0',
    'pose_coverage_ready":false',
    'skinning_input_complete":false',
    'bone_local_witness_authorized":false',
    'contact_phase_ready":false',
    'animation_correction_authorized":false',
    'runtime_authorized":false',
]
for token in required:
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'bottom_percent', 'lowest_row', 'near_white',
    'camera_position', 'camera_fov', 'viewport_size', 'percentile',
):
    assert forbidden not in s, forbidden

collect = s[s.index('func _collect_mesh'):]
assert 'if w <= 0.0: continue' in collect
assert 'if not per_bone.has(toe): continue' in collect
assert '>= 0.5' not in collect and '> 0.25' not in collect
assert 'for bone in per_bone.keys():' in collect
assert '"bone_index":int(bone)' in collect
assert '"bone_name":str(skeleton.get_bone_name(int(bone)))' in collect
assert '"weight":w' in collect
assert 'influences.sort_custom' in collect

# The integrity rail validates normalization only; it must not become a selector.
assert 'if abs(s - 1.0) > NORMALIZATION_TOLERANCE' in s
assert 'if normalization_violation_count != 0' in s
assert 'if abs(w' not in collect

for token in (
    '"pose_coverage_ready":false', '"skinning_input_complete":false',
    '"bone_local_witness_authorized":false', '"runtime_authorized":false',
    '"visual_approval_claimed":false', '"player_view_claimed":false',
):
    assert token in s
print('CIV1_RIGHTFOOT_FULL_SKIN_BASIS_CONTRACT_OK')