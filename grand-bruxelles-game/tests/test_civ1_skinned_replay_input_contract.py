from pathlib import Path

root = Path(__file__).parents[1]
p = root / 'tools' / 'classify_civ1_skinned_replay_inputs.py'
s = p.read_text()
workflow = (root.parent / '.github' / 'workflows' / 'grand-bruxelles-civ1-skinned-replay-input.yml').read_text()

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

# The replay-input classifier requires the v2 normalization-integrity schema. Pin the
# workflow to the actual GREEN v2 artifact so a stale v1 artifact cannot silently
# satisfy only the ZIP hash check and fail later before producing a diagnostic receipt.
assert 'actions/artifacts/10018435896/zip' in workflow
assert '3f73d2fedfb97522749ab0a525ff29230c43aeb7f5e05758e2ff97ad843f2586  /tmp/civ1replay/basis.zip' in workflow
assert 'actions/artifacts/10016180097/zip' not in workflow
assert '9e995a3275c64266a1f51aa1430871fa8287048431f6d58aa727ee6502cced9a  /tmp/civ1replay/basis.zip' not in workflow
assert '2>&1 | tee /tmp/civ1replay/out/classifier.log' in workflow

print('CIV1_SKINNED_REPLAY_INPUT_CONTRACT_OK')
