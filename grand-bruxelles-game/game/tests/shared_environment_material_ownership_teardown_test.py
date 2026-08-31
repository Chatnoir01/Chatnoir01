from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"

TARGETS = {
    "game/scripts/brussels_osm_facade_surface_runtime.gd": {
        "family": "brussels_osm_facade_surface_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_materials", "building.material == owned", "building.material = baseline", 'remove_meta("material_family")'],
        "apply_function": "_set_material_state",
        "required_apply_tokens": ["_owned_materials[instance_id] = owned"],
    },
    "game/scripts/brussels_osm_facade_articulation_runtime.gd": {
        "family": "brussels_osm_facade_articulation_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_materials", "building.material == owned", "building.material = baseline", 'remove_meta("facade_articulation_family")'],
        "apply_function": "_try_apply",
        "required_apply_tokens": ["_owned_materials[instance_id] = candidate"],
    },
    "game/scripts/brussels_osm_road_surface_runtime.gd": {
        "family": "brussels_osm_road_surface_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_materials", "road.material == owned", "road.material = _legacy_materials.get(instance_id) as Material", "_official_owned_materials", "instance.material_override == owned", "instance.material_override = _official_legacy_materials.get(instance_id) as Material", 'remove_meta("ground_network_presentation_family")'],
        "apply_function": "_set_material_state",
        "required_apply_tokens": ["_owned_materials[instance_id] = owned", "_official_owned_materials[instance_id] = owned"],
        "official_family": "brussels_ground_network_official_material_v1",
    },
    "game/scripts/brussels_base_ground_surface_runtime.gd": {
        "family": "brussels_base_ground_surface_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_ground.material == _enhanced_material", "_ground.material = _legacy_material", "_ground = null", "_legacy_material = null", "_enhanced_material = null"],
        "apply_function": "_set_material_state",
        "required_apply_tokens": ["var current := _ground.material", "current == _legacy_material or current == _enhanced_material", "_ground.material = _enhanced_material", "current == _enhanced_material or current == _legacy_material", "_ground.material = _legacy_material"],
    },
    "game/scripts/brussels_osm_sidewalk_surface_runtime.gd": {
        "family": "brussels_osm_sidewalk_surface_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_materials", "sidewalk.material == owned", "sidewalk.material = _legacy_materials.get(instance_id) as Material", "_official_owned_materials", "instance.material_override == owned", "instance.material_override = _official_legacy_materials.get(instance_id) as Material", 'remove_meta("ground_network_presentation_family")'],
        "apply_function": "_set_material_state",
        "required_apply_tokens": ["_owned_materials[instance_id] = _material", "_official_owned_materials[instance_id] = _official_material"],
        "official_family": "brussels_ground_network_official_material_v1",
    },
    "game/scripts/brussels_osm_rail_surface_runtime.gd": {
        "family": "brussels_osm_rail_surface_v1",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_materials", "rail.material == owned", "rail.material = _legacy_materials.get(instance_id) as Material", "_official_owned_materials", "instance.material_override == owned", "instance.material_override = _official_legacy_materials.get(instance_id) as Material", 'remove_meta("ground_network_presentation_family")'],
        "apply_function": "_set_material_state",
        "required_apply_tokens": ["_owned_materials[instance_id] = _enhanced_material", "_official_owned_materials[instance_id] = _official_material"],
        "official_family": "brussels_ground_network_official_material_v1",
    },
    "game/scripts/midi_architectural_concrete_surface_runtime.gd": {
        "family": "brussels_source_verified_architectural_concrete",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_restore_owned_materials()", "_owned_materials.clear()", "_original_material_overrides.clear()", "_targets.clear()", "_material = null"],
        "restore_function": "_restore_owned_materials",
        "required_restore_tokens": ["target.material_override == owned", "target.material_override = _original_material_overrides.get(instance_id) as Material"],
        "apply_function": "set_enhanced_material_enabled",
        "required_apply_tokens": ["_owned_materials[instance_id] = _material"],
    },
    "game/scripts/midi_blue_stone_surface_runtime.gd": {
        "family": "brussels_source_verified_blue_stone",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_restore_owned_materials()", "_owned_materials.clear()", "_original_material_overrides.clear()", "_targets.clear()", "_material = null"],
        "restore_function": "_restore_owned_materials",
        "required_restore_tokens": ["target.material_override == owned", "target.material_override = _original_material_overrides.get(instance_id) as Material"],
        "apply_function": "set_enhanced_material_enabled",
        "required_apply_tokens": ["_owned_materials[instance_id] = _material"],
    },
    "game/scripts/midi_architectural_glazing_surface_runtime.gd": {
        "family": "brussels_source_verified_architectural_glazing",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_restore_owned_materials()", "_owned_materials.clear()", "_original_material_overrides.clear()", "_targets.clear()", "_material = null"],
        "restore_function": "_restore_owned_materials",
        "required_restore_tokens": ["target.material_override == owned", "target.material_override = _original_material_overrides.get(instance_id) as Material"],
        "apply_function": "set_enhanced_material_enabled",
        "required_apply_tokens": ["_owned_materials[instance_id] = _material"],
    },
    "game/scripts/midi_fauquenberg_brick_surface_runtime.gd": {
        "family": "brussels_source_verified_fauquenberg_brick",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_restore_owned_materials()", "_owned_materials.clear()", "_original_materials.clear()", "_targets.clear()", "_material = null"],
        "restore_function": "_restore_owned_materials",
        "required_restore_tokens": ["mesh_instance.material_override == owned", "mesh_instance.material_override = _original_materials.get(instance_id) as Material"],
        "apply_function": "set_enhanced_material_enabled",
        "required_apply_tokens": ["_owned_materials[instance_id] = _material"],
    },
    "game/scripts/ixelles_midi_sidewalk_runtime.gd": {
        "family": "ixelles_midi_sidewalk_blue_stone_labo",
        "helper": "_release_material_ownership",
        "required_helper_tokens": ["_owned_material", "_target.material_override == _owned_material", "_target.material_override = _legacy_material", 'remove_meta("shared_sidewalk_material_owner")', "_target = null", "_legacy_material = null", "_owned_material = null", "_material = null"],
        "apply_function": "_apply_target",
        "required_apply_tokens": ["_legacy_material = target.material_override", "_owned_material = _material"],
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
        fail("shared Environment material-ownership teardown rail missing")
    if contract.get("material_ownership_registry_expected_count") != 11:
        fail("shared Environment material owner count lock missing or drifted")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment runtime registry missing")

    declared_owner_paths = {
        entry.get("path")
        for entry in runtimes
        if isinstance(entry, dict) and entry.get("material_ownership_teardown_cleanup_required") is True
    }
    if declared_owner_paths != set(TARGETS):
        fail(f"shared material owner registry differs from central owner regression: registry={sorted(declared_owner_paths)} test={sorted(TARGETS)}")

    validated: list[str] = []
    for target_path, expected in TARGETS.items():
        matching = [entry for entry in runtimes if isinstance(entry, dict) and entry.get("path") == target_path]
        if len(matching) != 1:
            fail(f"material owner runtime lifecycle entry missing or duplicated: {target_path}")
        entry = matching[0]
        if entry.get("material_ownership_teardown_cleanup_required") is not True:
            fail(f"material ownership cleanup requirement missing: {target_path}")
        if entry.get("material_ownership_cleanup_helper") != expected["helper"]:
            fail(f"material ownership cleanup helper drifted: {target_path}")
        if entry.get("owned_material_family") != expected["family"]:
            fail(f"owned material family drifted: {target_path}")
        if "official_family" in expected and entry.get("owned_official_material_family") != expected["official_family"]:
            fail(f"owned official material family drifted: {target_path}")

        source = (ROOT / target_path).read_text(encoding="utf-8")
        exit_body = function_body(source, "_exit_tree")
        if f"{expected['helper']}()" not in exit_body:
            fail(f"teardown does not release material ownership: {target_path}")

        helper_body = function_body(source, expected["helper"])
        for token in expected["required_helper_tokens"]:
            if token not in helper_body:
                fail(f"owner-aware release missing token in {target_path}: {token}")

        restore_function = expected.get("restore_function")
        if restore_function:
            restore_body = function_body(source, restore_function)
            if not restore_body:
                fail(f"owner-aware restore helper missing in {target_path}: {restore_function}")
            for token in expected.get("required_restore_tokens", []):
                if token not in restore_body:
                    fail(f"owner-aware restore missing token in {target_path}: {token}")

        apply_body = function_body(source, expected["apply_function"])
        for token in expected["required_apply_tokens"]:
            if token not in apply_body:
                fail(f"runtime does not persist exact owned material identity in {target_path}: {token}")
        validated.append(target_path)

    if len(validated) != 11:
        fail("expected exactly eleven shared material-owning runtimes")

    print("SHARED_ENVIRONMENT_MATERIAL_OWNERSHIP_TEARDOWN_OK: owners=11 owner_aware_restore=true geometry_changed=false")


if __name__ == "__main__":
    main()