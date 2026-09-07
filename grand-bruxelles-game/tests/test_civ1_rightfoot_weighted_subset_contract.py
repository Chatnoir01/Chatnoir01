import re
from pathlib import Path


def assert_no_tuned_weight_cutoff(source: str) -> None:
    patterns = (
        r"\bWEIGHT_THRESHOLD\b",
        r"\b(?:rightfoot_weight|stored_weight|skin_weight)\s*(?:>=|>)\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"[\"'](?:weight_threshold|rightfoot_weight_threshold)[\"']\s*:\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"threshold_tuned[\"']?\s*[:=]\s*true",
    )
    for pattern in patterns:
        assert re.search(pattern, source) is None, pattern


# Ordinary arithmetic remains legal; source selection cutoffs do not.
assert_no_tuned_weight_cutoff("return (a + b) * 0.5")
assert_no_tuned_weight_cutoff("if w <= 0.0:\n    continue")
for bad in (
    "if rightfoot_weight >= 0.5:\n    keep()",
    "if stored_weight > 0.25:\n    keep()",
    "const WEIGHT_THRESHOLD := 0.4",
    '"weight_threshold": 0.5',
    '"threshold_tuned": true',
):
    try:
        assert_no_tuned_weight_cutoff(bad)
    except AssertionError:
        pass
    else:
        raise AssertionError(f"tuned cutoff escaped regression: {bad}")

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_weighted_subset_probe.gd"
s = p.read_text()
required = [
    'const TARGET_BONE := "mixamorig_RightFoot"',
    'grand-bruxelles-civ1-skin-influence-census-v3',
    'all_stored_positive_skin_influences_resolved_through_skin_bind_to_skeleton_bone',
    'stored_weight_greater_than_zero_only',
    'mesh_ARRAY_BONES_is_skin_bind_index_then_skin_get_bind_bone_maps_to_skeleton_index',
    'skin.get_bind_bone(bind)',
    'positive_weight_slot_count',
    'invalid_positive_bind_slot_count',
    'target_rightfoot_positive_vertex_count',
    'right_side_positive_bones',
    'bone_influence_census',
    'threshold_tuned": false',
    'next_selection_authorized": false',
    'contact_phase_ready": false',
    'quantitative_foot_slide_candidate": false',
    'animation_correction_authorized": false',
    'runtime_authorized": false',
]
for token in required:
    assert token in s, token
for forbidden in (
    'fixed_vertices_whose_strongest_skin_influence_maps_to_mixamorig_RightFoot',
    'all_vertices_with_stored_nonzero_mixamorig_RightFoot_skin_influence',
    'no-dominant-rightfoot-vertices',
    'lowest_row',
    'near_white',
):
    assert forbidden not in s, forbidden

# Causal regression: ARRAY_BONES values are Skin bind indices, never Skeleton indices directly.
assert 'if bind == target_bone' not in s
assert 'skin.get_bind_bone(bind)' in s
assert 'var counters := {"invalid_positive_bind_slots": 0, "positive_weight_slots": 0}' in s
assert '_collect_meshes(root, skeleton, target_bone, census, target_vertices, mesh_keys, surface_keys, counters)' in s
assert_no_tuned_weight_cutoff(s)
print('CIV1_SKIN_INFLUENCE_CENSUS_CONTRACT_OK')
