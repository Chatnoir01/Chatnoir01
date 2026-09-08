#!/usr/bin/env python3
from pathlib import Path

p = Path('grand-bruxelles-game/tools/civ1_ground_geometry_phase_minima.py')
text = p.read_text()
required = [
    'grand-bruxelles-civ1-ground-geometry-windows-v1',
    'grand-bruxelles-civ1-ground-geometry-phase-minima-v1',
    'fixed_vertex_count',
    '3306',
    'raw_skinned_lower_envelope_y_m',
    'yb < ya and yb < yc',
    'local_minimum_indices',
    'lowest_candidate_sample_index',
    'kinematic_geometry_phase_candidate_only',
    'canonical_character_placement_available',
    'ground_contact_classifiable',
    'contact_proof_claimed',
    'planted_interval_claimable',
    'quantitative_foot_slide_candidate',
    'animation_correction_authorized',
    'runtime_authorized',
    'visual_approval_claimed',
    'player_view_claimed',
]
missing = [needle for needle in required if needle not in text]
assert not missing, f'missing contract markers: {missing}'

# No tolerance, percentile, camera/FOV, or bilateral-placement rescue is allowed in this phase classifier.
for forbidden in ['percentile', 'fov', 'camera', 'bilateral', 'placement_y']:
    assert forbidden not in text.lower(), f'forbidden rescue marker: {forbidden}'

print('CIV1_GROUND_GEOMETRY_PHASE_MINIMA_CONTRACT_OK')
