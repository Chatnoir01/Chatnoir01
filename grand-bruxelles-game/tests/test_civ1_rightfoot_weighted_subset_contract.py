from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_weighted_subset_probe.gd"
s = p.read_text()
required = [
    'const TARGET_BONE := "mixamorig_RightFoot"',
    'all_vertices_with_stored_nonzero_mixamorig_RightFoot_skin_influence',
    'stored_rightfoot_weight_greater_than_zero_only',
    'rightfoot_influenced_vertex_count',
    'dominant_rightfoot_vertex_count',
    'dominant_bone_counts_within_rightfoot_influenced_set',
    'rightfoot_weight_min',
    'rightfoot_weight_median',
    'rightfoot_weight_max',
    'threshold_tuned": false',
    'contact_phase_ready": false',
    'quantitative_foot_slide_candidate": false',
    'animation_correction_authorized": false',
    'runtime_authorized": false',
]
for token in required:
    assert token in s, token
for forbidden in (
    'fixed_vertices_whose_strongest_skin_influence_maps_to_mixamorig_RightFoot',
    'no-dominant-rightfoot-vertices',
    'WEIGHT_THRESHOLD',
    '0.5',
    '0.25',
    'lowest_row',
    'near_white',
):
    assert forbidden not in s, forbidden
assert 'rightfoot_weight <= 0.0' in s
assert 'dominant_rightfoot_semantic_valid' in s
print('CIV1_RIGHTFOOT_SKIN_INFLUENCE_CONTRACT_OK')
