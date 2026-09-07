from pathlib import Path
import re

p = Path(__file__).parents[1] / "tools" / "godot_civ1_righttoebase_pose_probe.gd"
s = p.read_text()

required = [
    'const FOOT := "mixamorig_RightFoot"',
    'const TOE := "mixamorig_RightToeBase"',
    'const TARGET_SAMPLES := [68, 69, 70, 71]',
    'const REQUIRED_FRAME_COUNT := 120',
    'skeleton.get_bone_parent(toe) != foot',
    'poses.has("RightToeBase")',
    'source_foot.affine_inverse() * source_toe',
    'corrected_foot * source_relative',
    'source-authored RightToeBase relative transform composed onto validated reconstructed RightFoot global pose',
    '"pose_coverage_ready":true',
    '"skinning_input_complete":false',
    '"bone_local_witness_authorized":false',
    '"contact_phase_ready":false',
    '"animation_correction_authorized":false',
    '"runtime_authorized":false',
    '"visual_approval_claimed":false',
    '"player_view_claimed":false',
]
for token in required:
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'bottom_percent', 'lowest_row', 'near_white',
    'camera_position', 'camera_fov', 'viewport_size', 'percentile',
    'set_bone_global_pose', 'set_bone_pose_position', 'set_bone_pose_rotation',
):
    assert forbidden not in s, forbidden

# Godot 4.7.1 treats inferred Variant warnings as errors in this diagnostic project.
# Runs 34128178050 and 34132440026 exposed three independent sites; lock all three.
assert 'var bundle: Variant = _read_json(args[0])' in s
assert 'var q: Quaternion = t.basis.get_rotation_quaternion().normalized()' in s
assert 'var value: Variant = JSON.parse_string(f.get_as_text())' in s
assert 'var bundle := _read_json(args[0])' not in s
assert 'var q := t.basis.get_rotation_quaternion().normalized()' not in s
assert 'var value := JSON.parse_string(f.get_as_text())' not in s

# Never synthesize a rigid toe by copying the validated RightFoot transform unchanged.
assert re.search(r'^\s*var\s+corrected_toe\s*:=\s*corrected_foot\s*$', s, re.MULTILINE) is None
assert 'var corrected_toe := corrected_foot * source_relative' in s
assert 'source_relative := source_foot.affine_inverse() * source_toe' in s

# The input bundle remains the validated 120-frame reconstruction and must not
# already contain RightToeBase; this gate adds exactly that missing coverage.
assert 'bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1"' in s
assert 'frames.size() != REQUIRED_FRAME_COUNT' in s
assert 'not poses.has("RightFoot") or poses.has("RightToeBase")' in s
print("CIV1_RIGHTTOEBASE_POSE_CONTRACT_OK")
