from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
EXPECTED = {
    "game/scripts/brussels_osm_road_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_sidewalk_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_osm_rail_surface_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_corridor_tree_runtime.gd": "_on_tree_node_removed",
    "game/scripts/brussels_street_lamp_runtime.gd": "_on_node_removed",
    "game/scripts/brussels_bollard_runtime.gd": "_on_node_removed",
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
        )
        if not purges_retained_state:
            fail(f"node_removed handler does not purge retained state: {rel_path}")

    unexpected = {
        entry.get("path")
        for entry in runtimes
        if isinstance(entry, dict) and entry.get("node_removed_cleanup_required") is True
    } - claimed
    if unexpected:
        fail(f"unexpected node_removed lifecycle claims: {sorted(unexpected)}")

    print(
        "SHARED_ENVIRONMENT_NODE_REMOVED_LIFECYCLE_OK: "
        f"runtimes={len(EXPECTED)} watcher_cleanup=locked retained_state_cleanup=locked"
    )


if __name__ == "__main__":
    main()
