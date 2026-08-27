from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game/scripts/midi_fauquenberg_brick_surface_runtime.gd"


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, function_name: str) -> str:
    marker = f"func {function_name}("
    lines = source.splitlines()
    start = next((i + 1 for i, line in enumerate(lines) if line.startswith(marker)), None)
    if start is None:
        return ""
    body: list[str] = []
    for line in lines[start:]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        body.append(line)
    return "\n".join(body)


def main() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    for token in (
        "const EXPECTED_SURFACES := 3",
        "var _owned_materials: Dictionary = {}",
        "func _release_material_ownership() -> void:",
        "func _restore_owned_materials() -> void:",
    ):
        if token not in source:
            fail(f"Fauquenberg material ownership contract missing: {token}")

    exit_body = function_body(source, "_exit_tree")
    if "_release_material_ownership()" not in exit_body:
        fail("Fauquenberg teardown does not release owned material")

    restore_body = function_body(source, "_restore_owned_materials")
    for token in (
        "mesh_instance.material_override == owned",
        "mesh_instance.material_override = _original_materials.get(instance_id) as Material",
    ):
        if token not in restore_body:
            fail(f"Fauquenberg owner-aware restore missing: {token}")

    release_body = function_body(source, "_release_material_ownership")
    for token in (
        "_restore_owned_materials()",
        "_owned_materials.clear()",
        "_original_materials.clear()",
        "_targets.clear()",
        "_material = null",
    ):
        if token not in release_body:
            fail(f"Fauquenberg release cleanup missing: {token}")

    toggle_body = function_body(source, "set_enhanced_material_enabled")
    for token in (
        "_owned_materials[instance_id] = _material",
        "elif owned != null and mesh_instance.material_override == owned",
    ):
        if token not in toggle_body:
            fail(f"Fauquenberg owner-aware toggle missing: {token}")

    print("MIDI_FAUQUENBERG_MATERIAL_OWNERSHIP_TEARDOWN_OK: surfaces=3 owner_aware_restore=true geometry_changed=false")


if __name__ == "__main__":
    main()
