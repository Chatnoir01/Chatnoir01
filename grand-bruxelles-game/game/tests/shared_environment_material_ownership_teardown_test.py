from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
ARTICULATION_PATH = ROOT / "game" / "scripts" / "brussels_osm_facade_articulation_runtime.gd"
TARGET_PATH = "game/scripts/brussels_osm_facade_articulation_runtime.gd"
TARGET_FAMILY = "brussels_osm_facade_articulation_v1"
TARGET_HELPER = "_release_material_ownership"


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
    matching = [entry for entry in runtimes if isinstance(entry, dict) and entry.get("path") == TARGET_PATH]
    if len(matching) != 1:
        fail("facade articulation runtime lifecycle entry missing or duplicated")
    entry = matching[0]
    if entry.get("material_ownership_teardown_cleanup_required") is not True:
        fail("facade articulation material ownership cleanup requirement missing")
    if entry.get("material_ownership_cleanup_helper") != TARGET_HELPER:
        fail("facade articulation material ownership cleanup helper drifted")
    if entry.get("owned_material_family") != TARGET_FAMILY:
        fail("facade articulation owned material family drifted")

    source = ARTICULATION_PATH.read_text(encoding="utf-8")
    exit_body = function_body(source, "_exit_tree")
    if f"{TARGET_HELPER}()" not in exit_body:
        fail("facade articulation teardown does not release material ownership")

    helper_body = function_body(source, TARGET_HELPER)
    required_tokens = (
        "_owned_materials",
        "building.material == owned",
        "building.material = baseline",
        'remove_meta("facade_articulation_family")',
    )
    for token in required_tokens:
        if token not in helper_body:
            fail(f"facade articulation owner-aware restore missing token: {token}")

    apply_body = function_body(source, "_try_apply")
    if "_owned_materials[instance_id] = candidate" not in apply_body:
        fail("facade articulation does not persist exact owned material identity")

    print(
        "SHARED_ENVIRONMENT_MATERIAL_OWNERSHIP_TEARDOWN_OK: "
        "runtime=BrusselsOsmFacadeArticulationRuntime family=%s owner_aware_restore=true "
        "geometry_changed=false" % TARGET_FAMILY
    )


if __name__ == "__main__":
    main()
