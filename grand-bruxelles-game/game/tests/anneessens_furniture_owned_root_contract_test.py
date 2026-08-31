from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
RUNTIME_PATH = ROOT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
RUNTIME_REL = "game/scripts/anneessens_osm_furniture_runtime.gd"
AUTOLOAD = "AnneessensOsmFurnitureRuntime"
OWNED_ROOT = "AnneessensOsmFurniture"
SOURCE = "OpenStreetMap contributors via Overpass API"
LICENSE = "ODbL-1.0"


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, function_name: str) -> str:
    lines = source.splitlines()
    marker = f"func {function_name}("
    start = None
    for index, line in enumerate(lines):
        if line.startswith(marker):
            start = index + 1
            break
    if start is None:
        return ""
    body: list[str] = []
    for line in lines[start:]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        body.append(line)
    return "\n".join(body)


def main() -> None:
    if not CONTRACT_PATH.is_file():
        fail("shared Environment lifecycle contract missing")
    if not RUNTIME_PATH.is_file():
        fail("Anneessens furniture runtime missing")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment lifecycle runtime registry missing")

    matches = [
        entry
        for entry in runtimes
        if isinstance(entry, dict)
        and entry.get("autoload_name") == AUTOLOAD
        and entry.get("path") == RUNTIME_REL
    ]
    if len(matches) != 1:
        fail("Anneessens furniture lifecycle identity missing or duplicated")
    entry = matches[0]
    if entry.get("runtime_owned_root_teardown_cleanup_required") is not True:
        fail("Anneessens furniture owned-root teardown is not fail-closed in lifecycle registry")
    if entry.get("owned_root_name") != OWNED_ROOT:
        fail("Anneessens furniture owned-root identity drifted")

    source = RUNTIME_PATH.read_text(encoding="utf-8")
    if f'"{OWNED_ROOT}"' not in source:
        fail("Anneessens furniture runtime no longer creates the registered owned root")
    if SOURCE not in source or LICENSE not in source:
        fail("Anneessens furniture source/license provenance drifted")
    for required in (
        'set_meta("placement_source_backed", true)',
        'set_meta("visual_dimensions_source_backed", false)',
        'set_meta("source_height_measured", false)',
        'set_meta("source_species_measured", false)',
    ):
        if required not in source:
            fail(f"Anneessens furniture provenance rail missing: {required}")

    exit_body = function_body(source, "_exit_tree")
    if "_release_owned_root()" not in exit_body:
        fail("Anneessens furniture owned root is not released synchronously from _exit_tree")

    cleanup = function_body(source, "_release_owned_root")
    for required in ("remove_child(", "queue_free()", "_trees.clear()", "_tree_materials.clear()"):
        if required not in cleanup:
            fail(f"Anneessens furniture owned-root cleanup incomplete: {required}")

    activation = function_body(source, "_apply_tree_activation")
    for required in (
        "_root.visible = active",
        "collision.disabled = not active",
    ):
        if required not in activation:
            fail(f"Anneessens tree visibility/collision synchronization missing: {required}")

    process_body = function_body(source, "_process")
    if "_apply_tree_activation(" not in process_body:
        fail("Anneessens distance activation bypasses collision synchronization")

    build_body = function_body(source, "_build_once")
    if "_apply_tree_activation(" not in build_body:
        fail("Anneessens newly built colliders do not inherit current activation state")

    print(
        "ANNEESSENS_FURNITURE_OWNED_ROOT_CONTRACT_OK: "
        f"autoload={AUTOLOAD} root={OWNED_ROOT} source=OSM license={LICENSE} "
        "detach_then_free=true tree_visibility_collision_sync=locked runtime_geometry_changed=false"
    )


if __name__ == "__main__":
    main()
