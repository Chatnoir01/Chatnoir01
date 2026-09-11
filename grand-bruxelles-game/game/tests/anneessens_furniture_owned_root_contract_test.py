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
COLLISION_POLICY = "disabled_until_source_backed_trunk_profile"


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
        'set_meta("collision_source_backed", false)',
        'set_meta("collision_authorized", false)',
        f'"{COLLISION_POLICY}"',
    ):
        if required not in source:
            fail(f"Anneessens furniture provenance/collision rail missing: {required}")

    create_tree = function_body(source, "_create_tree")
    if not create_tree:
        fail("Anneessens staged tree construction helper missing")
    if "tree.position = world_position" not in create_tree:
        fail("Anneessens staged tree no longer preserves validated source position")
    if "parent_root.add_child(tree)" not in create_tree:
        fail("Anneessens tree is not attached to the staged owned root before publication")
    for forbidden in ("CollisionShape3D.new()", "CylinderShape3D.new()", "_scene.add_child(tree)"):
        if forbidden in create_tree:
            fail(f"Anneessens staged tree ownership/collision contract regressed: {forbidden}")

    exit_body = function_body(source, "_exit_tree")
    if "_release_owned_root()" not in exit_body:
        fail("Anneessens furniture owned root is not released synchronously from _exit_tree")

    cleanup = function_body(source, "_release_owned_root")
    for required in ("remove_child(", "queue_free()", "_trees.clear()", "_tree_materials.clear()"):
        if required not in cleanup:
            fail(f"Anneessens furniture owned-root cleanup incomplete: {required}")

    activation = function_body(source, "_apply_tree_activation")
    if "_root.visible = active" not in activation:
        fail("Anneessens tree visibility activation drifted")
    if "CollisionShape3D" in activation or "collision.disabled" in activation:
        fail("Anneessens activation must not resurrect unsourced tree collision")

    process_body = function_body(source, "_process")
    if "_apply_tree_activation(" not in process_body:
        fail("Anneessens distance activation no longer drives owned-root visibility")

    build_body = function_body(source, "_build_once")
    required_build_fragments = (
        "var candidate_root := Node3D.new()",
        "candidate_trees.append(candidate_tree)",
        "candidate_root.visible = active",
        "_scene.add_child(candidate_root)",
        "_root = candidate_root",
        "_trees = candidate_trees",
    )
    for required in required_build_fragments:
        if required not in build_body:
            fail(f"Anneessens atomic owned-root publication rail missing: {required}")
    if not (
        build_body.index("candidate_trees.append(candidate_tree)")
        < build_body.index("_scene.add_child(candidate_root)")
        < build_body.index("_root = candidate_root")
        < build_body.index("_trees = candidate_trees")
    ):
        fail("Anneessens owned-root staging/publication/ownership order drifted")
    if "candidate_root.free()" not in build_body:
        fail("Anneessens failed staging path does not free the unpublished candidate root")

    print(
        "ANNEESSENS_FURNITURE_OWNED_ROOT_CONTRACT_OK: "
        f"autoload={AUTOLOAD} root={OWNED_ROOT} source=OSM license={LICENSE} "
        f"atomic_stage_publish_commit=true detach_then_free=true collision_policy={COLLISION_POLICY} "
        "proxy_collisions=0 runtime_geometry_changed=false"
    )


if __name__ == "__main__":
    main()
