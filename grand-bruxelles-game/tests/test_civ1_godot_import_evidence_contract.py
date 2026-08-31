from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-godot-import-evidence.yml"
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_import_probe.gd"

workflow = WORKFLOW.read_text(encoding="utf-8")
probe = PROBE.read_text(encoding="utf-8")

required_workflow_tokens = (
    "4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip",
    "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
    "^4\\.7\\.1\\.stable\\.official\\.",
    "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
    "--require-animations",
    "--headless --editor --path /tmp/civ1-godot/project --quit",
    "CIV1_GODOT_IMPORT_PROBE_OK",
    "assert evidence['godot_import_verified'] is False",
    "assert status['production_authorized'] is False",
    "test ! -e assets/characters/civilians/civ1/civ1.tscn",
    "test ! -e assets/characters/civilians/civ1/source/vitruvian_body_sanitized.glb",
)
for token in required_workflow_tokens:
    assert token in workflow, token

required_probe_tokens = (
    'const BODY_PATH := "res://vitruvian_body_sanitized.glb"',
    "node is Skeleton3D",
    "node is MeshInstance3D",
    "state.skeleton_count != 1",
    "state.bone_count <= 0",
    "state.skinned_mesh_count <= 0",
    "state.material_surface_count <= 0",
    '"integrity": "validated"',
)
for token in required_probe_tokens:
    assert token in probe, token

# The evidence gate must never promote the temporary binary into repository assets.
assert "cp /tmp/civ1-godot/project/vitruvian_body_sanitized.glb" not in workflow
assert "mv /tmp/civ1-godot/project/vitruvian_body_sanitized.glb" not in workflow

print("CIV1_GODOT_IMPORT_EVIDENCE_CONTRACT_OK")
