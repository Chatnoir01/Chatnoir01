from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_weighted_subset_probe.gd"
s = p.read_text()
required = [
    'const TARGET_BONE := "mixamorig_RightFoot"',
    'selection_semantic',
    'fixed_vertices_whose_strongest_skin_influence_maps_to_mixamorig_RightFoot',
    'threshold_tuned": false',
    'skin.get_bind_bone(strongest_bind) != target_bone',
    'strongest_weight',
    'contact_phase_ready": false',
    'quantitative_foot_slide_candidate": false',
    'animation_correction_authorized": false',
    'runtime_authorized": false',
]
for token in required:
    assert token in s, token
for forbidden in ('WEIGHT_THRESHOLD', '0.5', '0.25', 'lowest_row', 'near_white'):
    assert forbidden not in s, forbidden
print('CIV1_RIGHTFOOT_WEIGHTED_SUBSET_CONTRACT_OK')
