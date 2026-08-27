from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
DEFERRED_RECOVERY_FUNCTIONS = {
    "game/scripts/brussels_osm_road_surface_runtime.gd": ("_schedule_road_bind", "_recover_existing_roads"),
    "game/scripts/brussels_osm_sidewalk_surface_runtime.gd": ("_schedule_sidewalk_bind", "_recover_existing_sidewalks"),
    "game/scripts/brussels_osm_rail_surface_runtime.gd": ("_schedule_rail_bind", "_recover_existing_rails"),
}
BOUNDED_WAIT_FUNCTIONS = {
    "game/scripts/midi_blue_stone_surface_runtime.gd": "_apply_when_subtree_ready",
    "game/scripts/midi_architectural_concrete_surface_runtime.gd": "_apply_when_subtree_ready",
    "game/scripts/midi_architectural_glazing_surface_runtime.gd": "_apply_when_subtree_ready",
    "game/scripts/midi_fauquenberg_brick_surface_runtime.gd": "_apply_when_subtree_ready",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, function_name: str) -> str:
    match = re.search(rf"^func {re.escape(function_name)}\([^\n]*\) -> void:\n(?P<body>(?:^(?:    |\t).*\n?)*)", source, re.MULTILINE)
    return match.group("body") if match else ""


def has_guarded_node_added_disconnect(source: str, exit_body: str) -> bool:
    """Accept direct teardown cleanup or a helper explicitly called by _exit_tree.

    Terminal-bind runtimes often share one watcher-disconnect helper between
    successful binding and teardown. The lifecycle contract cares that teardown
    reaches a guarded disconnect, not that the statements are duplicated inline.
    """
    if "node_added.is_connected(" in exit_body and "node_added.disconnect(" in exit_body:
        return True
    for helper_name in re.findall(r"\b(_[A-Za-z0-9_]+)\(", exit_body):
        helper_body = function_body(source, helper_name)
        if "node_added.is_connected(" in helper_body and "node_added.disconnect(" in helper_body:
            return True
    return False


def main() -> None:
    if not CONTRACT_PATH.is_file():
        fail("shared Environment lifecycle contract missing")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("node_added_watcher_cleanup_required") is not True:
        fail("shared Environment node_added watcher cleanup contract missing")
    if contract.get("watcher_retention_semantics_explicit") is not True:
        fail("shared Environment watcher retention semantics are not explicit")
    if contract.get("deferred_recovery_teardown_guard_required") is not True:
        fail("shared Environment deferred recovery teardown guard contract missing")
    if contract.get("bounded_subtree_wait_teardown_guard_required") is not True:
        fail("shared Environment bounded subtree wait teardown guard contract missing")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list) or not runtimes:
        fail("shared Environment lifecycle runtime registry missing")

    verified = 0
    teardown_verified = 0
    deferred_guard_verified = 0
    bounded_wait_verified = 0
    for entry in runtimes:
        if not isinstance(entry, dict):
            fail("malformed shared Environment lifecycle runtime entry")
        rel_path = entry.get("path")
        if not isinstance(rel_path, str) or not rel_path.startswith("game/scripts/"):
            fail(f"invalid shared Environment lifecycle runtime path: {rel_path}")

        script_path = ROOT / rel_path
        if not script_path.is_file():
            fail(f"registered shared Environment runtime missing: {rel_path}")
        source = script_path.read_text(encoding="utf-8")

        if "node_added.connect(" not in source:
            fail(f"registered runtime lost node_added watcher: {rel_path}")
        if "node_added.is_connected(" not in source:
            fail(f"node_added watcher cleanup guard missing: {rel_path}")
        if "node_added.disconnect(" not in source:
            fail(f"node_added watcher disconnect missing: {rel_path}")

        if entry.get("teardown_cleanup_required") is True:
            if entry.get("late_child_bind") is not True:
                fail(f"teardown watcher must be a late-child runtime: {rel_path}")
            exit_body = function_body(source, "_exit_tree")
            if not exit_body:
                fail(f"runtime-lifetime watcher lacks teardown cleanup function: {rel_path}")
            if not has_guarded_node_added_disconnect(source, exit_body):
                fail(f"runtime-lifetime watcher teardown does not reach guarded disconnect: {rel_path}")
            if "_tearing_down = true" not in exit_body:
                fail(f"runtime-lifetime watcher teardown does not cancel deferred recovery: {rel_path}")

            recovery_functions = DEFERRED_RECOVERY_FUNCTIONS.get(rel_path)
            if recovery_functions is None:
                fail(f"runtime-lifetime watcher missing deferred recovery contract mapping: {rel_path}")
            schedule_name, recover_name = recovery_functions
            schedule_body = function_body(source, schedule_name)
            recover_body = function_body(source, recover_name)
            if not schedule_body or "_tearing_down" not in schedule_body:
                fail(f"deferred recovery scheduler lacks teardown guard: {rel_path}")
            if not recover_body or "_tearing_down" not in recover_body or "is_inside_tree()" not in recover_body:
                fail(f"deferred recovery callback lacks teardown/tree guard: {rel_path}")
            teardown_verified += 1
            deferred_guard_verified += 1

        if entry.get("bounded_wait_teardown_guard_required") is True:
            wait_name = BOUNDED_WAIT_FUNCTIONS.get(rel_path)
            if wait_name is None:
                fail(f"bounded-wait runtime missing contract mapping: {rel_path}")
            wait_body = function_body(source, wait_name)
            exit_body = function_body(source, "_exit_tree")
            if not wait_body or "await" not in wait_body:
                fail(f"bounded-wait runtime lost expected local await path: {rel_path}")
            if not exit_body or "_tearing_down = true" not in exit_body:
                fail(f"bounded-wait runtime lacks teardown cancellation: {rel_path}")
            if not has_guarded_node_added_disconnect(source, exit_body):
                fail(f"bounded-wait runtime teardown does not reach guarded watcher disconnect: {rel_path}")
            if "_tearing_down" not in wait_body or "is_inside_tree()" not in wait_body:
                fail(f"bounded subtree wait can continue after teardown: {rel_path}")
            bounded_wait_verified += 1

        verified += 1

    if verified != int(contract.get("registered_runtime_count", -1)):
        fail(
            "shared Environment watcher cleanup coverage mismatch: "
            f"verified={verified} registered={contract.get('registered_runtime_count')}"
        )
    if teardown_verified != 3:
        fail(f"expected exactly three runtime-lifetime watcher teardowns, got {teardown_verified}")
    if deferred_guard_verified != 3:
        fail(f"expected exactly three deferred recovery teardown guards, got {deferred_guard_verified}")
    if bounded_wait_verified != 4:
        fail(f"expected exactly four bounded Midi wait teardown guards, got {bounded_wait_verified}")

    print(
        "SHARED_ENVIRONMENT_WATCHER_CLEANUP_OK: "
        f"runtimes={verified} runtime_lifetime_teardown={teardown_verified} "
        f"deferred_recovery_guarded={deferred_guard_verified} bounded_wait_guarded={bounded_wait_verified} "
        "connect=guarded disconnect=explicit_or_verified_delegate"
    )


if __name__ == "__main__":
    main()
