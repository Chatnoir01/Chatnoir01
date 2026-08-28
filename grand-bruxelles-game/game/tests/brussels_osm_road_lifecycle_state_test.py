from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_road_surface_runtime.gd"


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
    if not RUNTIME.is_file():
        fail("Brussels OSM road surface runtime missing")
    source = RUNTIME.read_text(encoding="utf-8")

    ready_body = function_body(source, "_ready")
    if "get_tree().node_removed.is_connected(_on_node_removed)" not in ready_body:
        fail("road runtime does not check individual node removal subscription")
    if "get_tree().node_removed.connect(_on_node_removed)" not in ready_body:
        fail("road runtime does not subscribe to individual node removal")

    exit_body = function_body(source, "_exit_tree")
    if "tree.node_removed.is_connected(_on_node_removed)" not in exit_body:
        fail("road runtime does not check node removal watcher during teardown")
    if "tree.node_removed.disconnect(_on_node_removed)" not in exit_body:
        fail("road runtime does not disconnect node removal watcher on teardown")

    removed_body = function_body(source, "_on_node_removed")
    if not removed_body:
        fail("individual road node removal cleanup helper missing")

    for token in (
        "_roads.erase(node)",
        "_legacy_materials.erase(instance_id)",
        "_owned_materials.erase(instance_id)",
        "_roles.erase(instance_id)",
        "_official_nodes.erase(instance_id)",
        "_official_legacy_materials.erase(instance_id)",
        "_official_owned_materials.erase(instance_id)",
        "_official_roles.erase(instance_id)",
    ):
        if token not in removed_body:
            fail(f"individual road removal leaves stale lifecycle state: missing {token}")

    print("BRUSSELS_OSM_ROAD_LIFECYCLE_STATE_OK: node_removal_cleanup=true generated_state=true official_state=true")


if __name__ == "__main__":
    main()
