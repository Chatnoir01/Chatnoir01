from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_corridor_tree_runtime.gd"


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
    source = RUNTIME.read_text(encoding="utf-8")

    ready = function_body(source, "_ready")
    if "node_removed" not in ready or "connect" not in ready:
        fail("corridor tree runtime does not subscribe to SceneTree.node_removed")

    exit_body = function_body(source, "_exit_tree")
    if "node_removed" not in exit_body or "disconnect" not in exit_body:
        fail("corridor tree runtime does not disconnect SceneTree.node_removed at teardown")

    removed = function_body(source, "_on_tree_node_removed")
    if not removed:
        fail("corridor tree scene-removal handler missing")
    for token in ("_release_owned_root()", "_scene = null", "_ready_complete = false", "_start_scene_watch"):
        if token not in removed:
            fail(f"corridor tree scene removal does not restore rebindable state: missing {token}")

    process_body = function_body(source, "_process")
    if "is_instance_valid(_scene)" not in process_body:
        fail("corridor tree per-frame path does not fail closed on a freed production scene")

    node_added = function_body(source, "_on_tree_node_added")
    if 'call_deferred("_try_bind_scene"' not in node_added:
        fail("corridor tree node_added path can build synchronously while production parents are still setting up children")
    if "_try_bind_scene(_production_scene_from_node(node))" in node_added:
        fail("corridor tree node_added path still performs synchronous scene binding")

    try_bind = function_body(source, "_try_bind_scene")
    for token in ("_tearing_down", "not is_inside_tree()", "_ready_complete"):
        if token not in try_bind:
            fail(f"deferred corridor tree bind is missing teardown/idempotence guard: {token}")

    print("BRUSSELS_CORRIDOR_TREE_SCENE_REBIND_OK: scene_removal_cleanup=true rebind=true stale_scene_guard=true node_added_reentrant_safe=true")


if __name__ == "__main__":
    main()
