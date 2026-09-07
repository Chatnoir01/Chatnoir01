from pathlib import Path

p = Path(__file__).parents[1] / "tools" / "civ1_ground_contact_reference_classifier.py"
s = p.read_text()
required = [
    'REPLAY_SAMPLES = [68, 69, 70, 71]',
    'REQUIRED_VERTEX_COUNT = 3306',
    'grand-bruxelles-civ1-ground-contact-reference-v1',
    'source_ground_reference_present',
    'canonical_ground_reference_ready = False',
    'same_sample_contact_evidence',
    'grounding_verified',
    'planted_contact_claimed',
    '"quantitative_foot_slide_candidate": quantitative_foot_slide_candidate',
    '"animation_correction_authorized": False',
    '"runtime_authorized": False',
    '"visual_approval_claimed": False',
    '"player_view_claimed": False',
    'source_ground_node_has_no_numeric_world_plane_or_collider_transform_in_consumed_evidence',
    'replay_samples_68_71_do_not_overlap_landmark_samples_114_118',
]
for token in required:
    assert token in s, token
for forbidden in (
    'WEIGHT_THRESHOLD', 'percentile', 'bottom_percent', 'lowest_row',
    'camera_position', 'camera_fov', 'viewport_size',
    'quantitative_foot_slide_candidate = True',
    '"animation_correction_authorized": True',
    '"runtime_authorized": True',
    'canonical_ground_reference_ready = True',
):
    assert forbidden not in s, forbidden
print('CIV1_GROUND_CONTACT_REFERENCE_CONTRACT_OK')
