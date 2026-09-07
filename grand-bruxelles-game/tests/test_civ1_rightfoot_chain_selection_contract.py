import importlib.util
from pathlib import Path

ROOT = Path(__file__).parents[1]
TOOL = ROOT / "tools" / "classify_civ1_rightfoot_chain_selection.py"
spec = importlib.util.spec_from_file_location("selector", TOOL)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

base = {
    "schema": "grand-bruxelles-civ1-rightfoot-chain-geometry-v5",
    "threshold_tuned": False,
    "toe_is_descendant_of_rightfoot": True,
    "positive_weight_slot_count": 139856,
    "resolved_positive_bind_slot_count": 139856,
    "unresolved_positive_bind_slot_count": 0,
    "target_rightfoot_positive_vertex_count": 2087,
    "righttoebase_positive_vertex_count": 3306,
    "chain_overlap_vertex_count": 2087,
    "rightfoot_only_vertex_count": 0,
    "righttoebase_only_vertex_count": 1219,
    "chain_union_vertex_count": 3306,
    "chain_union_vertices": [{"mesh_path": "m", "surface": 1, "vertex": i} for i in range(3306)],
    "contact_phase_ready": False,
    "quantitative_foot_slide_candidate": False,
    "animation_correction_authorized": False,
    "runtime_authorized": False,
    "visual_approval_claimed": False,
    "player_view_claimed": False,
}

out = selector.classify(base)
assert out["rightfoot_is_strict_subset_of_righttoebase"] is True
assert out["selection_vertex_count"] == 3306
assert out["selection_equivalence"] == "chain_union_equals_righttoebase_positive_vertex_set"
assert out["next_selection_authorized"] is True
assert out["authorized_next_use"] == "bone_local_contact_stability_witness_only"
assert out["minimum_stable_samples_required"] == 3
for key in ("contact_phase_ready", "quantitative_foot_slide_candidate", "animation_correction_authorized", "runtime_authorized", "visual_approval_claimed", "player_view_claimed"):
    assert out[key] is False

for mutation in (
    {"rightfoot_only_vertex_count": 1},
    {"chain_overlap_vertex_count": 2086},
    {"chain_union_vertex_count": 3307},
    {"threshold_tuned": True},
    {"unresolved_positive_bind_slot_count": 1},
    {"contact_phase_ready": True},
):
    bad = dict(base)
    bad.update(mutation)
    try:
        selector.classify(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"fail-open mutation escaped: {mutation}")

source = TOOL.read_text()
# Guard actual rescue mechanisms, not harmless provenance/receipt field names.
for forbidden in (
    "bottom_percent",
    "near_white",
    "camera_position",
    "camera_fov",
    "viewport_size",
    "viewport_width",
    "viewport_height",
    "WEIGHT_THRESHOLD",
):
    assert forbidden not in source, forbidden
assert '"weight_cutoff_used": False' in source
assert '"raster_or_camera_heuristic_used": False' in source
print("CIV1_RIGHTFOOT_CHAIN_SELECTION_V1_CONTRACT_OK")
