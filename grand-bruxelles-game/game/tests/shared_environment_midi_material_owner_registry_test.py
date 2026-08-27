from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"

EXPECTED = {
    "game/scripts/midi_blue_stone_surface_runtime.gd": {
        "autoload": "MidiBlueStoneSurfaceRuntime",
        "family": "brussels_source_verified_blue_stone",
        "surface_count_token": "EXPECTED_SURFACES := 3",
        "restore_tokens": (
            "target.material_override == owned",
            "target.material_override = _original_material_overrides.get(instance_id) as Material",
        ),
        "release_tokens": (
            "_restore_owned_materials()",
            "_owned_materials.clear()",
            "_original_material_overrides.clear()",
            "_targets.clear()",
            "_material = null",
        ),
        "toggle_tokens": (
            "_owned_materials[instance_id] = _material",
            "elif owned != null and target.material_override == owned",
        ),
    },
    "game/scripts/midi_architectural_glazing_surface_runtime.gd": {
        "autoload": "MidiArchitecturalGlazingSurfaceRuntime",
        "family": "brussels_source_verified_architectural_glazing",
        "surface_count_token": "EXPECTED_SURFACES := 340",
        "restore_tokens": (
            "target.material_override == owned",
            "target.material_override = _original_material_overrides.get(instance_id) as Material",
        ),
        "release_tokens": (
            "_restore_owned_materials()",
            "_owned_materials.clear()",
            "_original_material_overrides.clear()",
            "_targets.clear()",
            "_material = null",
        ),
        "toggle_tokens": (
            "_owned_materials[instance_id] = _material",
            "elif owned != null and target.material_override == owned",
        ),
    },
    "game/scripts/midi_fauquenberg_brick_surface_runtime.gd": {
        "autoload": "MidiFauquenbergBrickSurfaceRuntime",
        "family": "brussels_source_verified_fauquenberg_brick",
        "surface_count_token": "EXPECTED_SURFACES := 3",
        "restore_tokens": (
            "mesh_instance.material_override == owned",
            "mesh_instance.material_override = _original_materials.get(instance_id) as Material",
        ),
        "release_tokens": (
            "_restore_owned_materials()",
            "_owned_materials.clear()",
            "_original_materials.clear()",
            "_targets.clear()",
            "_material = null",
        ),
        "toggle_tokens": (
            "_owned_materials[instance_id] = _material",
            "elif owned != null and mesh_instance.material_override == owned",
        ),
    },
}


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
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("runtime_material_ownership_teardown_cleanup_required") is not True:
        fail("global material ownership teardown rail missing")
    if contract.get("material_ownership_registry_expected_count") != 10:
        fail("shared material owner registry count is not durably locked to 10")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment lifecycle runtime registry missing")

    declared_owners = [
        entry for entry in runtimes
        if isinstance(entry, dict) and entry.get("material_ownership_teardown_cleanup_required") is True
    ]
    if len(declared_owners) != 10:
        fail(f"expected exactly 10 declared shared material owners, got {len(declared_owners)}")

    for path, expected in EXPECTED.items():
        matches = [entry for entry in runtimes if isinstance(entry, dict) and entry.get("path") == path]
        if len(matches) != 1:
            fail(f"lifecycle entry missing or duplicated: {path}")
        entry = matches[0]
        if entry.get("autoload_name") != expected["autoload"]:
            fail(f"autoload identity drifted: {path}")
        if entry.get("material_ownership_teardown_cleanup_required") is not True:
            fail(f"material ownership teardown requirement missing: {path}")
        if entry.get("material_ownership_cleanup_helper") != "_release_material_ownership":
            fail(f"material ownership helper drifted: {path}")
        if entry.get("owned_material_family") != expected["family"]:
            fail(f"owned material family drifted: {path}")

        source = (ROOT / path).read_text(encoding="utf-8")
        if expected["surface_count_token"] not in source:
            fail(f"source-backed target count drifted: {path}")

        exit_body = function_body(source, "_exit_tree")
        if "_release_material_ownership()" not in exit_body:
            fail(f"teardown no longer releases material ownership: {path}")

        restore_body = function_body(source, "_restore_owned_materials")
        for token in expected["restore_tokens"]:
            if token not in restore_body:
                fail(f"owner-aware restore drifted in {path}: {token}")

        release_body = function_body(source, "_release_material_ownership")
        for token in expected["release_tokens"]:
            if token not in release_body:
                fail(f"ownership release cleanup drifted in {path}: {token}")

        toggle_body = function_body(source, "set_enhanced_material_enabled")
        for token in expected["toggle_tokens"]:
            if token not in toggle_body:
                fail(f"owner-aware toggle drifted in {path}: {token}")

    print(
        "SHARED_ENVIRONMENT_MIDI_MATERIAL_OWNER_REGISTRY_OK: "
        "owners=10 blue_stone=3 glazing=340 fauquenberg=3 "
        "owner_aware_restore=true geometry_changed=false"
    )


if __name__ == "__main__":
    main()
