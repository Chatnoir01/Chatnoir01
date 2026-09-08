from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "godot_civ1_righttoebase_full_pose_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-righttoebase-full-pose.yml"

s = SCRIPT.read_text(encoding="utf-8")
w = WORKFLOW.read_text(encoding="utf-8")

for token in (
    'const FOOT := "mixamorig_RightFoot"',
    'const TOE := "mixamorig_RightToeBase"',
    'const REQUIRED_FRAME_COUNT := 120',
    'for sample_index in range(REQUIRED_FRAME_COUNT):',
    'skeleton.get_bone_parent(toe) != foot',
    'not poses.has("RightFoot") or poses.has("RightToeBase")',
    'source_foot.affine_inverse() * source_toe',
    'corrected_foot * source_relative',
    '"schema":"grand-bruxelles-civ1-righttoebase-full-pose-v1"',
    '"full_pose_coverage_ready":samples.size() == REQUIRED_FRAME_COUNT',
    '"full_rotation_coverage_ready":samples.size() == REQUIRED_FRAME_COUNT',
    '"same_sample_ground_geometry_ready":samples.size() == REQUIRED_FRAME_COUNT',
    '"contact_proof_claimed":false',
    '"planted_interval_claimable":false',
    '"quantitative_foot_slide_candidate":false',
    '"animation_correction_authorized":false',
    '"runtime_authorized":false',
    '"visual_approval_claimed":false',
    '"player_view_claimed":false',
):
    assert token in s, token

for forbidden in (
    'WEIGHT_THRESHOLD', 'percentile', 'camera_position', 'camera_fov',
    'viewport_size', 'set_bone_global_pose', 'set_bone_pose_position',
    'set_bone_pose_rotation', 'rigid toe',
):
    assert forbidden not in s, forbidden

assert 'var bundle: Variant = _read_json(args[0])' in s
assert 'var value: Variant = JSON.parse_string(f.get_as_text())' in s
assert 'var q: Quaternion = t.basis.get_rotation_quaternion().normalized()' in s
assert re.search(r'^\s*var\s+corrected_toe\s*:=\s*corrected_foot\s*$', s, re.MULTILINE) is None

for token in (
    '1a2210270477f3e20b5127a42a7b3e13000a624c',
    '9996432028',
    '9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00',
    'bdecdcd537b4031fdd0fb299b7e4f93f084fffa0',
    '09bcade1092e5a89b474e91e6013209d4c68c127',
    'c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba',
    "assert r['frame_count']==120",
    "assert len(r['samples'])==120",
    "assert r['sample_indices']==list(range(120))",
):
    assert token in w, token

print('CIV1_RIGHTTOEBASE_FULL_POSE_CONTRACT_OK')