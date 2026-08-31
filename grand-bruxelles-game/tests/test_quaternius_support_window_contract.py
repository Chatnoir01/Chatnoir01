from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_quaternius_support_window_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-quaternius-support-window.yml"

assert PROBE.exists(), "missing support-window probe"
assert WORKFLOW.exists(), "missing support-window workflow"

probe = PROBE.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")

for needle in [
    'const SAMPLE_COUNT := 241',
    'const SUPPORT_BAND_FRACTION := 0.10',
    'await process_frame',
    'get_bone_global_pose',
    '"support_plane_definition": "minimum_bilateral_source_local_foot_height_per_clip"',
    '"support_window_definition": "contiguous_nonterminal_samples_within_bottom_10_percent_of_foot_vertical_excursion"',
    '"world_ground_assumed": false',
    '"contact_verified": false',
    '"grounding_verified": false',
    '"foot_slide_verified": false',
    '"semantic_selection_allowed": false',
    '"selected_run_alias": ""',
    '"civ1_retarget_authorized": false',
]:
    assert needle in probe, f"missing probe contract: {needle}"

for forbidden in [
    '"world_ground_assumed": true',
    '"contact_verified": true',
    '"grounding_verified": true',
    '"foot_slide_verified": true',
    '"semantic_selection_allowed": true',
    '"civ1_retarget_authorized": true',
]:
    assert forbidden not in probe, f"unsafe rail opened: {forbidden}"

for needle in [
    'Grand Bruxelles Quaternius Support Windows',
    'Godot_v4.7.1-stable_linux.x86_64.zip',
    'f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767',
    'QUATERNIUS_SUPPORT_WINDOWS_OK',
    'minimum_bilateral_source_local_foot_height_per_clip',
    'contiguous_nonterminal_samples_within_bottom_10_percent_of_foot_vertical_excursion',
    'contact_verified',
    'grounding_verified',
    'foot_slide_verified',
]:
    assert needle in workflow, f"missing workflow contract: {needle}"

print("QUATERNIUS_SUPPORT_WINDOW_CONTRACT_OK")
