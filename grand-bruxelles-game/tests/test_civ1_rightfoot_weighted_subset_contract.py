import re
from pathlib import Path


def assert_no_tuned_weight_cutoff(source: str) -> None:
    patterns = (
        r"\bWEIGHT_THRESHOLD\b",
        r"\b(?:rightfoot_weight|righttoebase_weight|stored_weight|skin_weight)\s*(?:>=|>)\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"[\"'](?:weight_threshold|rightfoot_weight_threshold|righttoebase_weight_threshold)[\"']\s*:\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"threshold_tuned[\"']?\s*[:=]\s*true",
    )
    for pattern in patterns:
        assert re.search(pattern, source) is None, pattern


assert_no_tuned_weight_cutoff("return (a + b) * 0.5")
assert_no_tuned_weight_cutoff("if w <= 0.0:\n    continue")
for bad in (
    "if rightfoot_weight >= 0.5:\n    keep()",
    "if righttoebase_weight > 0.25:\n    keep()",
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
    'const TOE_BONE := "mixamorig_RightToeBase"',
    'grand-bruxelles-civ1-rightfoot-chain-geometry-v5',
    'fixed_vertex_ids_with_stored_positive_influence_on_real_skeleton_chain_rightfoot_to_righttoebase',
    'skeleton_parent_topology_only_no_name_guess_no_weight_cutoff',
    'stored_weight_greater_than_zero_only',
    'ARRAY_BONES_is_skin_bind_index_then_resolve_get_bind_bone_or_get_bind_name_to_skeleton',
    'skin.get_bind_bone(bind)',
    'skin.get_bind_name(bind)',
    'skeleton.find_bone(bind_name)',
    'func _is_descendant_of',
    'skeleton.get_bone_parent(current)',
    'toe_is_descendant_of_rightfoot',
    'chain_union_vertex_count',
    'chain_overlap_vertex_count',
    'rightfoot_only_vertex_count',
    'righttoebase_only_vertex_count',
    'chain_union_accounting_valid',
    '"mesh_path": str(mi.get_path())',
    '"surface": surface',
    '"vertex": vi',
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
    'lowest_row',
    'bottom_percent',
    'near_white',
    'if bind == target_bone',
    'camera',
    'viewport',
):
    assert forbidden not in s, forbidden

# Named Skin binds must continue to resolve through the Skeleton.
resolver_start = s.index('func _resolve_bind_bone')
resolver_end = s.index('func _collect_meshes', resolver_start)
resolver = s[resolver_start:resolver_end]
assert resolver.index('skin.get_bind_bone(bind)') < resolver.index('skin.get_bind_name(bind)')
assert resolver.index('skin.get_bind_name(bind)') < resolver.index('skeleton.find_bone(bind_name)')
assert 'if indexed_bone >= 0 and indexed_bone < skeleton.get_bone_count()' in resolver
assert 'if not bind_name.is_empty()' in resolver

# The chain relation itself must come from parent topology, not string prefix matching.
chain_start = s.index('func _is_descendant_of')
chain_end = s.index('func _resolve_bind_bone', chain_start)
chain = s[chain_start:chain_end]
assert 'skeleton.get_bone_parent(current)' in chain
assert '"Right" in' not in chain
assert 'TOE_BONE' not in chain

# Fixed union/exclusive sets must be partitioned from positive stored influence only.
collect_start = s.index('func _collect_mesh(mi:')
collect = s[collect_start:]
assert 'var has_foot := per_vertex.has(target_bone)' in collect
assert 'var has_toe := per_vertex.has(toe_bone)' in collect
assert 'if has_foot and has_toe:' in collect
assert 'elif has_foot:' in collect
assert 'righttoebase_only_vertices.append' in collect
assert 'p.y <' not in collect.split('var has_foot :=', 1)[1]

# Accounting and all downstream promotion remain fail-closed.
assert 'chain_union_vertices.size() == union_expected' in s
assert 'chain_union_vertices.size() == partition_expected' in s
assert 'resolved_slots != int(counters["positive_weight_slots"])' in s
assert 'int(counters["unresolved_positive_bind_slots"]) != 0' in s
assert_no_tuned_weight_cutoff(s)
print('CIV1_RIGHTFOOT_CHAIN_GEOMETRY_V5_CONTRACT_OK')
