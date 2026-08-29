from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
EXPECTED = {
    "game/scripts/midi_blue_stone_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_road_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_sidewalk_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_rail_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_corridor_tree_runtime.gd": "_on_tree_node_removed",
    "game/scripts/brussels_street_lamp_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_bollard_runtime.gd": "_on_node_removed",
    "game/scripts/anneessens_osm_furniture_runtime.gd": "_on_tree_node_removed",
    "game/scripts/brussels_base_ground_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_facade_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_facade_articulation_runtime.gd": "_on_node_removed",
}
HELPER_WATCHERS = {
    "game/scripts/midi_blue_stone_surface_runtime.gd",
    "game/scripts/anneessens_osm_furniture_runtime.gd",
    "game/scripts/brussels_base_ground_surface_runtime.gd",
    "game/scripts/brussels_osm_facade_surface_runtime.gd",
    "game/scripts/brussels_osm_facade_articulation_runtime.gd",
}
HELPER_REBIND_TOKENS = {
    "game/scripts/midi_blue_stone_surface_runtime.gd": (
        "_release_material_ownership()",
        "_midi_root = null",
        "_ready_complete = false",
        "_awaiting_midi = true",
        "_start_watching()",
        'call_deferred("_bind_existing_midi")',
    ),
    "game/scripts/anneessens_osm_furniture_runtime.gd": (
        "_reset()",
        "_start_watching()",
        'call_deferred("_try_bind")',
    ),
    "game/scripts/brussels_base_ground_surface_runtime.gd": (
        "_release_material_ownership()",
        "_ready_complete = false",
        "_failed = false",
        "_awaiting_main = true",
        "_start_watching()",
        'call_deferred("_bind_existing_main")',
    ),
    "game/scripts/brussels_osm_facade_surface_runtime.gd": (
        "_release_material_ownership()",
        "_buildings_root = null",
        "_ready_complete = false",
        "_start_watching()",
        'call_deferred("_try_apply")',
    ),
    "game/scripts/brussels_osm_facade_articulation_runtime.gd": (
        "_release_material_ownership()",
        "_buildings_root = null",
        "_ready_complete = false",
        "_start_watching()",
        "_connect_base_runtime()",
        'call_deferred("_try_apply")',
    ),
}
STREET_FURNITURE_REBIND = {
    "game/scripts/brussels_street_lamp_runtime.gd",
    "game/scripts/brussels_bollard_runtime.gd",
}


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
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("node_removed_watcher_cleanup_required") is not True:
        fail("central lifecycle contract does not require node_removed cleanup")
    if contract.get("node_removed_registry_runtime_count") != len(EXPECTED):
        fail("node_removed registry runtime count drifted")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment lifecycle runtime registry missing")
    by_path = {entry.get("path"): entry for entry in runtimes if isinstance(entry, dict)}

    claimed: set[str] = set()
    for rel_path, handler in EXPECTED.items():
        entry = by_path.get(rel_path)
        if not isinstance(entry, dict):
            fail(f"node_removed runtime missing from lifecycle registry: {rel_path}")
        if entry.get("node_removed_cleanup_required") is not True:
            fail(f"node_removed cleanup requirement missing: {rel_path}")
        if entry.get("node_removed_cleanup_handler") != handler:
            fail(f"node_removed cleanup handler drifted: {rel_path}")
        claimed.add(rel_path)

        source_path = ROOT / rel_path
        source = source_path.read_text(encoding="utf-8")
        ready_body = function_body(source, "_ready")
        exit_body = function_body(source, "_exit_tree")
        handler_body = function_body(source, handler)

        if rel_path in HELPER_WATCHERS:
            start_body = function_body(source, "_start_watching")
            stop_body = function_body(source, "_stop_watching")
            if "_start_watching()" not in ready_body:
                fail(f"node_removed watcher helper not armed from _ready: {rel_path}")
            if "_stop_watching()" not in exit_body:
                fail(f"node_removed watcher helper not stopped from _exit_tree: {rel_path}")
            if f"node_removed.connect({handler})" not in start_body:
                fail(f"node_removed watcher not connected from helper: {rel_path}")
            if f"node_removed.disconnect({handler})" not in stop_body:
                fail(f"node_removed watcher not disconnected from helper: {rel_path}")
        else:
            if f"node_removed.connect({handler})" not in ready_body:
                fail(f"node_removed watcher not connected from _ready: {rel_path}")
            if f"node_removed.disconnect({handler})" not in exit_body:
                fail(f"node_removed watcher not disconnected from _exit_tree: {rel_path}")

        if not handler_body:
            fail(f"node_removed cleanup handler missing: {rel_path}")
        purges_retained_state = (
            ".erase(" in handler_body
            or ".clear()" in handler_body
            or "_release_owned_root()" in handler_body
            or "_reset()" in handler_body
            or "_release_material_ownership()" in handler_body
        )
        if not purges_retained_state:
            fail(f"node_removed handler does not purge retained state: {rel_path}")

        for token in HELPER_REBIND_TOKENS.get(rel_path, ()):
            if token not in handler_body:
                fail(f"helper-watcher node_removed handler is not rebindable: {rel_path} missing {token}")

        if rel_path in STREET_FURNITURE_REBIND:
            for token in (
                "_scene = null",
                "_ready_complete = false",
                "node_added.connect(_on_node_added)",
                "_schedule_scene_bind()",
            ):
                if token not in handler_body:
                    fail(f"street-furniture node_removed handler is not rebindable: {rel_path} missing {token}")
            build_body = function_body(source, "_build")
            if "is_instance_valid(_scene)" not in build_body:
                fail(f"street-furniture build path does not fail closed on freed scene: {rel_path}")

    unexpected = {
        entry.get("path")
        for entry in runtimes
        if isinstance(entry, dict) and entry.get("node_removed_cleanup_required") is True
    } - claimed
    if unexpected:
        fail(f"unexpected node_removed lifecycle claims: {sorted(unexpected)}")

    print(
        "SHARED_ENVIRONMENT_NODE_REMOVED_LIFECYCLE_OK: "
        f"runtimes={len(EXPECTED)} watcher_cleanup=locked retained_state_cleanup=locked helper_watchers={len(HELPER_WATCHERS)} street_furniture_rebind=locked"
    )


if __name__ == "__main__":
    main()
