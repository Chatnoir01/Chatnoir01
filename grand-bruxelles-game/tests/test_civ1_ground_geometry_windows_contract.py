#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_ground_geometry_windows_probe.gd"
WF = ROOT / ".github/workflows/grand-bruxelles-civ1-ground-geometry-windows.yml"

probe = PROBE.read_text(encoding="utf-8")
wf = WF.read_text(encoding="utf-8")

for token in [
    'grand-bruxelles-civ1-ground-geometry-windows-v1',
    'REQUIRED_VERTEX_COUNT := 3306',
    'grand-bruxelles-civ1-righttoebase-full-pose-v1',
    'same_sample_ground_geometry_ready',
    'canonical_character_placement_available":false',
    'contact_proof_claimed":false',
    'animation_correction_authorized":false',
    'runtime_authorized":false',
    'player_view_claimed":false',
]:
    assert token in probe, token

for token in [
    '10031928117', '9996432028', '10053292431', '10051214336', '10037379556',
    '1a2210270477f3e20b5127a42a7b3e13000a624c',
    'c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba',
    'CIV1_GROUND_GEOMETRY_WINDOWS_OK',
]:
    assert token in wf, token

# This witness must not silently revive the rejected bilateral placement as Ground truth.
assert 'bilateral_placement_y_m' not in probe
assert 'placement_y_m' not in probe
print('CIV1_GROUND_GEOMETRY_WINDOWS_CONTRACT_OK')
