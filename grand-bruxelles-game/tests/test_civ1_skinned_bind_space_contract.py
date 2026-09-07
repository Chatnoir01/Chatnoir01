from pathlib import Path

root = Path(__file__).parents[1]
script = (root / "tools" / "classify_civ1_skinned_bind_space.py").read_text()
workflow = (root.parent / ".github" / "workflows" / "grand-bruxelles-civ1-skinned-bind-space.yml").read_text()

required = [
    'BASIS_SCHEMA = "grand-bruxelles-civ1-rightfoot-full-skin-basis-v2"',
    'COVERAGE_SCHEMA = "grand-bruxelles-civ1-skinned-replay-input-coverage-v1"',
    'REQUIRED_SAMPLES = [68, 69, 70, 71]',
    'basis["selection_vertex_count"] == 3306',
    'coverage["missing_required_pose_bones"] == []',
    'coverage["bone_local_witness_authorized"] is True',
    '"inverse_bind_transform"',
    '"inverse_bind_matrix"',
    '"bind_transform"',
    '"bone_global_rest"',
    '"mesh_to_skeleton_rest"',
    '"rigid_parent_proxy_authorized": False',
    '"global_pose_as_bind_matrix_authorized": False',
    '"skinned_replay_authorized": bind_space_complete',
    '"animation_correction_authorized": False',
    '"runtime_authorized": False',
    '"visual_approval_claimed": False',
    '"player_view_claimed": False',
]
for token in required:
    assert token in script, token

for forbidden in (
    "WEIGHT_THRESHOLD", "bottom_percent", "lowest_row", "near_white",
    "camera_position", "camera_fov", "viewport_size", "percentile",
):
    assert forbidden not in script, forbidden

assert '"skinned_replay_authorized": True' not in script
assert 'vertices_with_bind_space == 3306' in script
assert 'influence_slots_with_bind_space == influence_slots' in script
assert "actions/artifacts/10018435896/zip" in workflow
assert "3f73d2fedfb97522749ab0a525ff29230c43aeb7f5e05758e2ff97ad843f2586" in workflow
assert "actions/artifacts/10028018308/zip" in workflow
assert "cb3d00edab93dcb731d85fcf9986930cd11c271e25b18f02f14666c59a60a62a" in workflow
assert "actions/artifacts/10016180097/zip" not in workflow

print("CIV1_SKINNED_BIND_SPACE_CONTRACT_OK")
