import re
from pathlib import Path


def assert_no_tuned_weight_cutoff(source: str) -> None:
    patterns = (
        r"\bWEIGHT_THRESHOLD\b",
        r"\brightfoot_weight\s*(?:>=|>)\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"[\"'](?:weight_threshold|rightfoot_weight_threshold)[\"']\s*:\s*(?:0\.(?!0+\b)\d+|[1-9]\d*(?:\.\d+)?)",
        r"threshold_tuned[\"']?\s*[:=]\s*true",
    )
    for pattern in patterns:
        assert re.search(pattern, source) is None, pattern


# Regression: numeric 0.5 used for ordinary median/interpolation math is valid.
assert_no_tuned_weight_cutoff("return (values[mid - 1] + values[mid]) * 0.5")
assert_no_tuned_weight_cutoff("if rightfoot_weight <= 0.0:\n    continue")

# Regression: source-weight selection cutoffs remain forbidden regardless of spelling.
for bad in (
    "if rightfoot_weight >= 0.5:\n    keep()",
    "if rightfoot_weight > 0.25:\n    keep()",
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
    'lowest_row',
    'near_white',
):
    assert forbidden not in s, forbidden
assert_no_tuned_weight_cutoff(s)
assert 'rightfoot_weight <= 0.0' in s
assert 'dominant_rightfoot_semantic_valid' in s
print('CIV1_RIGHTFOOT_SKIN_INFLUENCE_CONTRACT_OK')
