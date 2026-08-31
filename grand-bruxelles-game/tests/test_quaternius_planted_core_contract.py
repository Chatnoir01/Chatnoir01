from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "grand-bruxelles-game/tools/godot_quaternius_planted_core_probe.gd"
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-quaternius-planted-core.yml"

assert PROBE.exists(), "RED: planted-core Godot probe is missing"
assert WORKFLOW.exists(), "RED: planted-core workflow is missing"

probe = PROBE.read_text()
workflow = WORKFLOW.read_text()

for token in (
    "const SAMPLE_COUNT := 121",
    "const CORE_TRIM_FRACTION := 0.25",
    '"grand-bruxelles-quaternius-planted-core-v1"',
    '"diagnostic_only": true',
    '"world_ground_assumed": false',
    '"contact_verified": false',
    '"semantic_selection_allowed": false',
    '"selected_run_alias": ""',
    '"civ1_retarget_authorized": false',
    '"grounding_verified": false',
    '"foot_slide_verified": false',
    '"visual_approval_claimed": false',
):
    assert token in probe, f"missing fail-closed planted-core contract token: {token}"

assert "force_update_all_bone_transforms" not in probe
assert "core_sample_indices" in probe
assert "edge_segment_speed_mps_median" in probe
assert "core_segment_speed_mps_median" in probe
assert "core_segment_speed_mps_max" in probe
assert "support_window_wraps_cycle" in probe

for token in (
    "test_quaternius_planted_core_contract.py",
    "godot_quaternius_planted_core_probe.gd",
    "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
    "38687957",
    "4.7.1-stable",
    "QUATERNIUS_PLANTED_CORE_OK",
    "quaternius-planted-core-evidence",
):
    assert token in workflow, f"workflow missing pinned evidence token: {token}"

print("QUATERNIUS_PLANTED_CORE_CONTRACT_OK")
