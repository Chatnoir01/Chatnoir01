from pathlib import Path

p = Path(__file__).parents[1] / 'tools' / 'classify_civ1_skinned_replay_inputs.py'
s = p.read_text()

required = [
    "SAMPLES = [68, 69, 70, 71]",
    "grand-bruxelles-civ1-rightfoot-full-skin-basis-v2",
    "grand-bruxelles-civ1-skeleton-witness-bundle-v1",
    "grand-bruxelles-civ1-righttoebase-pose-v1",
    "basis['selection_vertex_count'] == 3306",
    "basis['full_vertex_influence_basis_integrity_ready'] is True",
    "basis['normalization_violation_count'] == 0",
    "float(inf['weight']) > 0.0",
    "available = set(poses.keys()) | {'RightToeBase'}",
    "missing = sorted(required - available)",
    "'skinning_input_complete': not missing_union",
    "'bone_local_witness_authorized': not missing_union",
    "'contact_phase_ready': False",
    "'animation_correction_authorized': False",
    "'runtime_authorized': False",
    "'visual_approval_claimed': False",
    "'player_view_claimed': False",
]
for token in required:
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'bottom_percent', 'lowest_row', 'near_white',
    'camera_position', 'camera_fov', 'viewport_size', 'percentile',
):
    assert forbidden not in s, forbidden

assert "required.add(short_bone(str(inf['bone_name'])))" in s
assert "len(set(ids)) == 3306" in s
assert "set(SAMPLES).issubset(toe_samples)" in s
print('CIV1_SKINNED_REPLAY_INPUT_CONTRACT_OK')
