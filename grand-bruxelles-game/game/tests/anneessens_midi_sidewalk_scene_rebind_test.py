from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


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
    if "node_removed.connect(_on_tree_node_removed)" not in ready:
        fail("Anneessens-Midi sidewalk runtime does not subscribe to SceneTree.node_removed")

    exit_body = function_body(source, "_exit_tree")
    if "node_removed.disconnect(_on_tree_node_removed)" not in exit_body:
        fail("Anneessens-Midi sidewalk runtime does not disconnect SceneTree.node_removed at teardown")

    handler = function_body(source, "_on_tree_node_removed")
    if not handler:
        fail("Anneessens-Midi sidewalk runtime has no production-scene removal handler")
    for token in (
        "_release_owned_root()",
        "_scene = null",
        "_bind_scheduled = false",
        "node_added.connect(_on_node_added)",
        "_schedule_bind()",
    ):
        if token not in handler:
            fail(f"Anneessens-Midi sidewalk scene removal does not restore rebindable state: missing {token}")

    build = function_body(source, "_build_from_existing_osm_roads")
    if "is_instance_valid(_scene)" not in build:
        fail("Anneessens-Midi sidewalk build path does not fail closed on a freed production scene")

    print(
        "ANNEESSENS_MIDI_SIDEWALK_SCENE_REBIND_OK: "
        "scene_removal_cleanup=true rebind=true stale_scene_guard=true"
    )


if __name__ == "__main__":
    main()
