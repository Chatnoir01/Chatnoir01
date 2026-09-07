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
    'grand-bruxelles-civ1-skin-influence-census-v4',
    'all_stored_positive_skin_influences_resolved_through_skin_bind_index_or_bind_name',
    'stored_weight_greater_than_zero_only',
    'ARRAY_BONES_is_skin_bind_index_then_resolve_get_bind_bone_or_get_bind_name_to_skeleton',
    'skin.get_bind_bone(bind)',
    'skin.get_bind_name(bind)',
    'skeleton.find_bone(bind_name)',
    'indexed_bind_resolution_slot_count',
    'named_bind_resolution_slot_count',
    'unresolved_positive_bind_slot_count',
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
    'if bind == target_bone',
):
    assert forbidden not in s, forbidden

# Causal regression for this RED: get_bind_bone() may be -1 for named binds.
# A failed indexed lookup must fall through to get_bind_name() + Skeleton.find_bone().
resolver_start = s.index('func _resolve_bind_bone')
resolver_end = s.index('func _collect_meshes', resolver_start)
resolver = s[resolver_start:resolver_end]
assert resolver.index('skin.get_bind_bone(bind)') < resolver.index('skin.get_bind_name(bind)')
assert resolver.index('skin.get_bind_name(bind)') < resolver.index('skeleton.find_bone(bind_name)')
assert 'if indexed_bone >= 0 and indexed_bone < skeleton.get_bone_count()' in resolver
assert 'if not bind_name.is_empty()' in resolver
assert 'unresolved_positive_bind_slots' in resolver

# Accounting must fail closed: every positive slot is indexed, named, or unresolved.
assert 'resolved_slots != int(counters["positive_weight_slots"])' in s
assert 'int(counters["unresolved_positive_bind_slots"]) != 0' in s
assert_no_tuned_weight_cutoff(s)
print('CIV1_SKIN_INFLUENCE_CENSUS_V4_CONTRACT_OK')
