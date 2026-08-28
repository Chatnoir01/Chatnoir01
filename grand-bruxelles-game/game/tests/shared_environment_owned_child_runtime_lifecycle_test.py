from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"

EXPECTED_CHILD = {
    "path": "game/scripts/midi_fonsny_full_entrance_runtime.gd",
    "owner_runtime_path": "game/scripts/midi_architectural_concrete_surface_runtime.gd",
    "owner_accessor": "fonsny_full_entrance_runtime",
    "owned_root_name": "EntranceSourceBackedFonsnyPorch",
    "release_helper": "_release_owned_replacement",
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
    if contract.get("owned_child_runtime_teardown_cleanup_required") is not True:
        fail("owned child runtime teardown lifecycle rail missing")
    if contract.get("registered_owned_child_runtime_count") != 1:
        fail("owned child runtime count must be exactly 1")

    entries = contract.get("owned_child_runtimes")
    if not isinstance(entries, list) or len(entries) != 1:
        fail("owned child runtime registry must contain exactly one entry")
    entry = entries[0]
    for key, expected in EXPECTED_CHILD.items():
        if entry.get(key) != expected:
            fail(f"owned child runtime contract drifted: {key} expected={expected} actual={entry.get(key)}")
    if entry.get("teardown_cleanup_required") is not True:
        fail("Fonsny child runtime teardown cleanup must remain required")
    if entry.get("visibility_cleanup_before_release") is not True:
        fail("Fonsny visibility ownership cleanup ordering must remain required")

    child_path = ROOT / EXPECTED_CHILD["path"]
    owner_path = ROOT / EXPECTED_CHILD["owner_runtime_path"]
    if not child_path.is_file() or not owner_path.is_file():
        fail("Fonsny child or parent runtime missing")
    child = child_path.read_text(encoding="utf-8")
    owner = owner_path.read_text(encoding="utf-8")

    accessor_body = function_body(owner, EXPECTED_CHILD["owner_accessor"])
    if "_fonsny_full_entrance_runtime" not in accessor_body:
        fail("concrete runtime no longer exposes the exact owned Fonsny child")

    root_name = EXPECTED_CHILD["owned_root_name"]
    if f'REPLACEMENT_NAME := "{root_name}"' not in child:
        fail("Fonsny owned root identity drifted")

    exit_body = function_body(child, "_exit_tree")
    helper = EXPECTED_CHILD["release_helper"]
    if f"{helper}()" not in exit_body:
        fail("Fonsny owned replacement cleanup no longer runs from _exit_tree")

    release_body = function_body(child, helper)
    visibility_call = "set_replacement_enabled(false)"
    remove_call = "remove_child(_replacement)"
    free_call = "_replacement.queue_free()"
    for token in (visibility_call, remove_call, free_call):
        if token not in release_body:
            fail(f"Fonsny owned replacement cleanup missing token: {token}")
    if not (release_body.index(visibility_call) < release_body.index(remove_call) < release_body.index(free_call)):
        fail("Fonsny cleanup must restore presentation before detach then free")

    print("SHARED_ENVIRONMENT_OWNED_CHILD_RUNTIME_LIFECYCLE_OK count=1 root=EntranceSourceBackedFonsnyPorch")


if __name__ == "__main__":
    main()
