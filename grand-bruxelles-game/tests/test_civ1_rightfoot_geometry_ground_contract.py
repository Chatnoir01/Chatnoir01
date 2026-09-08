from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "godot_civ1_rightfoot_geometry_ground_probe.gd"
assert p.exists(), p
s = p.read_text()

required = [
    'const TARGET_SAMPLES := [68, 69, 70, 71]',
    'const REQUIRED_VERTEX_COUNT := 3306',
    'grand-bruxelles-civ1-rightfoot-geometry-ground-v1',
    'posed_bone_global * inverse_bind * mesh_to_skeleton_rest * source_vertex',
    'geometry_lower_envelope_clearance_m',
    'below_ground_vertex_count',
    'lower_envelope_vertex_id',
    'geometry_below_ground_sample_count',
    '"landmark_only_explanation_rejected":geometry_below_ground_sample_count > 0',
    '"quantitative_foot_slide_candidate":false',
    '"animation_correction_authorized":false',
    '"runtime_authorized":false',
    '"visual_approval_claimed":false',
    '"player_view_claimed":false',
]
for token in required:
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'percentile', 'bottom_percent', 'lowest_row',
    'camera_position', 'camera_fov', 'viewport_size',
    '"quantitative_foot_slide_candidate":true',
    '"animation_correction_authorized":true',
    '"runtime_authorized":true',
):
    assert forbidden not in s, forbidden

assert 'if world_position.y < ground_top_y:' in s
assert 'min_clearance_m = min(min_clearance_m, world_position.y - ground_top_y)' in s
assert 'abs(weight_sum - 1.0) > WEIGHT_SUM_TOLERANCE' in s
print('CIV1_RIGHTFOOT_GEOMETRY_GROUND_CONTRACT_OK')
