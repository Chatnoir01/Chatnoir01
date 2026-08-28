from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIMES = {
    "street lamp": ROOT / "game" / "scripts" / "brussels_street_lamp_runtime.gd",
    "bollard": ROOT / "game" / "scripts" / "brussels_bollard_runtime.gd",
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


def validate_runtime(label: str, path: Path) -> None:
    source = path.read_text(encoding="utf-8")

    ready = function_body(source, "_ready")
    if "node_removed" not in ready or "connect" not in ready:
        fail(f"{label} runtime does not subscribe to SceneTree.node_removed")

    exit_body = function_body(source, "_exit_tree")
    if "node_removed" not in exit_body or "disconnect" not in exit_body:
        fail(f"{label} runtime does not disconnect SceneTree.node_removed at teardown")

    handler = function_body(source, "_on_node_removed")
    if not handler:
        fail(f"{label} runtime has no production-scene removal handler")
    for token in ("_release_owned_root()", "_scene = null", "_ready_complete = false", "_schedule_scene_bind"):
        if token not in handler:
            fail(f"{label} scene removal does not restore rebindable state: missing {token}")

    build = function_body(source, "_build")
    if "is_instance_valid(_scene)" not in build:
        fail(f"{label} build path does not fail closed on a freed production scene")


for runtime_label, runtime_path in RUNTIMES.items():
    validate_runtime(runtime_label, runtime_path)

print("BRUSSELS_STREET_FURNITURE_SCENE_REBIND_OK: runtimes=2 scene_removal_cleanup=true rebind=true stale_scene_guard=true")
