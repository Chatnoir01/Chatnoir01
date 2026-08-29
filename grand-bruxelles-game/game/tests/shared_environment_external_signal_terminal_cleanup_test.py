from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
RUNTIME_PATH = ROOT / "game" / "scripts" / "brussels_osm_facade_articulation_runtime.gd"
RUNTIME_REL = "game/scripts/brussels_osm_facade_articulation_runtime.gd"
SIGNAL_NAME = "facade_surface_ready"
HELPER_NAME = "_disconnect_base_runtime"


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, name: str) -> str:
    lines = source.splitlines()
    marker = f"func {name}("
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
    if contract.get("external_runtime_signal_terminal_cleanup_required") is not True:
        fail("terminal external-runtime signal cleanup rail missing")

    entries = [entry for entry in contract.get("runtimes", []) if entry.get("path") == RUNTIME_REL]
    if len(entries) != 1:
        fail("facade articulation lifecycle entry missing or duplicated")
    entry = entries[0]
    if entry.get("external_signal_teardown_cleanup_required") is not True:
        fail("facade articulation teardown signal cleanup contract missing")
    if entry.get("external_signal_terminal_cleanup_required") is not False:
        fail("facade articulation scene-rebind signal retention must be explicit")
    if entry.get("external_signal_name") != SIGNAL_NAME:
        fail("facade articulation external signal identity drifted")
    if entry.get("external_signal_cleanup_helper") != HELPER_NAME:
        fail("facade articulation cleanup helper identity drifted")

    source = RUNTIME_PATH.read_text(encoding="utf-8")
    helper = function_body(source, HELPER_NAME)
    if SIGNAL_NAME not in helper or "disconnect(" not in helper:
        fail("facade articulation cleanup helper no longer disconnects base signal")

    exit_body = function_body(source, "_exit_tree")
    if HELPER_NAME + "()" not in exit_body:
        fail("facade articulation teardown no longer disconnects base signal")

    apply_body = function_body(source, "_try_apply")
    ready_index = apply_body.find("_ready_complete = true")
    cleanup_index = apply_body.find(f"{HELPER_NAME}()")
    if ready_index < 0:
        fail("facade articulation terminal ready marker missing")
    if cleanup_index >= 0:
        fail("facade articulation external signal must stay connected after terminal success for scene rebind")

    print(
        "SHARED_ENVIRONMENT_EXTERNAL_SIGNAL_TERMINAL_CLEANUP_OK: "
        "runtime=BrusselsOsmFacadeArticulationRuntime "
        "signal=facade_surface_ready terminal_cleanup=false teardown_cleanup=true scene_rebind_retained=true"
    )


if __name__ == "__main__":
    main()
