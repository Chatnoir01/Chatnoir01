from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"

TARGETS = {
    "game/scripts/brussels_osm_facade_surface_runtime.gd": {
        "family": "brussels_osm_facade_surface_v1",
        "helper": "_release_material_ownership",
        "owned_registry": "_owned_materials",
        "apply_function": "_set_material_state",
        "apply_token": "_owned_materials[instance_id] = owned",
        "restore_token": "building.material = baseline",
        "meta_token": 'remove_meta("material_family")',
    },
    "game/scripts/brussels_osm_facade_articulation_runtime.gd": {
        "family": "brussels_osm_facade_articulation_v1",
        "helper": "_release_material_ownership",
        "owned_registry": "_owned_materials",
        "apply_function": "_try_apply",
        "apply_token": "_owned_materials[instance_id] = candidate",
        "restore_token": "building.material = baseline",
        "meta_token": 'remove_meta("facade_articulation_family")',
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

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment runtime registry missing")

    validated: list[str] = []
    for target_path, expected in TARGETS.items():
        matching = [
            entry
            for entry in runtimes
            if isinstance(entry, dict) and entry.get("path") == target_path
        ]
        if len(matching) != 1:
            fail(f"material owner runtime lifecycle entry missing or duplicated: {target_path}")
        entry = matching[0]
        if entry.get("material_ownership_teardown_cleanup_required") is not True:
            fail(f"material ownership cleanup requirement missing: {target_path}")
        if entry.get("material_ownership_cleanup_helper") != expected["helper"]:
            fail(f"material ownership cleanup helper drifted: {target_path}")
        if entry.get("owned_material_family") != expected["family"]:
            fail(f"owned material family drifted: {target_path}")

        source_path = ROOT / target_path
        source = source_path.read_text(encoding="utf-8")
        exit_body = function_body(source, "_exit_tree")
        if f"{expected['helper']}()" not in exit_body:
            fail(f"teardown does not release material ownership: {target_path}")

        helper_body = function_body(source, expected["helper"])
        required_tokens = (
            expected["owned_registry"],
            "building.material == owned",
            expected["restore_token"],
            expected["meta_token"],
        )
        for token in required_tokens:
            if token not in helper_body:
                fail(f"owner-aware restore missing token in {target_path}: {token}")

        apply_body = function_body(source, expected["apply_function"])
        if expected["apply_token"] not in apply_body:
            fail(f"runtime does not persist exact owned material identity: {target_path}")

        validated.append(target_path)

    if len(validated) != 2:
        fail("expected exactly two shared facade material owners")

    print(
        "SHARED_ENVIRONMENT_MATERIAL_OWNERSHIP_TEARDOWN_OK: "
        "owners=2 surface_family=brussels_osm_facade_surface_v1 "
        "articulation_family=brussels_osm_facade_articulation_v1 "
        "owner_aware_restore=true geometry_changed=false"
    )


if __name__ == "__main__":
    main()
