from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_quaternius_low_foot_speed_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-quaternius-low-foot-speed.yml"

probe = PROBE.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")

required_probe = [
    'const SAMPLE_COUNT := 121',
    'const LOW_BAND_FRACTION := 0.10',
    'await process_frame',
    'get_bone_global_pose',
    'var min_y: float = ys.min()',
    'var max_y: float = ys.max()',
    'var threshold: float = min_y + (max_y - min_y) * LOW_BAND_FRACTION',
    'for i in range(1, samples.size() - 1):',
    '"terminal_loop_sample_excluded_from_speed": true',
    'source_relative_bottom_10_percent_of_each_foot_vertical_excursion',
    '"diagnostic_only": true',
    '"world_ground_assumed": false',
    '"semantic_selection_allowed": false',
    '"selected_run_alias": ""',
    '"civ1_retarget_authorized": false',
    '"grounding_verified": false',
    '"foot_slide_verified": false',
    '"visual_approval_claimed": false',
]
for needle in required_probe:
    assert needle in probe, f"missing probe contract: {needle}"

assert 'for i in range(1, samples.size()):' not in probe, "terminal loop sample can contaminate speed"

for forbidden in [
    'semantic_selection_allowed": true',
    'civ1_retarget_authorized": true',
    'grounding_verified": true',
    'foot_slide_verified": true',
    'visual_approval_claimed": true',
]:
    assert forbidden not in probe, f"unsafe rail opened: {forbidden}"

required_workflow = [
    "Grand Bruxelles Quaternius Low Foot Speed",
    "Godot_v4.7.1-stable_linux.x86_64.zip",
    "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
    "QUATERNIUS_LOW_FOOT_SPEED_OK",
    "terminal_loop_sample_excluded_from_speed",
    "world_ground_assumed",
    "semantic_selection_allowed",
    "foot_slide_verified",
]
for needle in required_workflow:
    assert needle in workflow, f"missing workflow contract: {needle}"

print("QUATERNIUS_LOW_FOOT_SPEED_CONTRACT_OK")
