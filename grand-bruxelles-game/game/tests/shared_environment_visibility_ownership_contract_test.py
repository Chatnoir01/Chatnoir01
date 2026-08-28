from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_visibility_ownership_contract.json"
RUNTIME_PATH = ROOT / "game" / "scripts" / "midi_fonsny_full_entrance_runtime.gd"


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, name: str) -> str:
    marker = f"func {name}("
    lines = source.splitlines()
    start = next((i + 1 for i, line in enumerate(lines) if line.startswith(marker)), None)
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
        fail("shared Environment visibility ownership contract missing")
    if not RUNTIME_PATH.is_file():
        fail("Fonsny visibility owner runtime missing")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-shared-environment-visibility-ownership-v1":
        fail("visibility ownership schema mismatch")
    if contract.get("visibility_ownership_registry_expected_count") != 1:
        fail("visibility ownership registry count mismatch")
    if contract.get("normal_player_visual_change_authorized") is not False:
        fail("visibility ownership QA must not authorize visual changes")
    if contract.get("geometry_or_collision_change_authorized") is not False:
        fail("visibility ownership QA must not authorize geometry/collision changes")

    owners = contract.get("owners")
    if not isinstance(owners, list) or len(owners) != 1:
        fail("exactly one shared visibility owner must be registered")
    owner = owners[0]
    expected = {
        "runtime_path": "game/scripts/midi_fonsny_full_entrance_runtime.gd",
        "owner_meta": "fonsny_visibility_owner",
        "owner_value": "midi_fonsny_full_entrance_runtime",
        "baseline_store": "_original_visibility",
        "cleanup_helper": "_release_superseded_visibility_ownership",
        "owned_replacement_root": "EntranceSourceBackedFonsnyPorch",
    }
    for key, value in expected.items():
        if owner.get(key) != value:
            fail(f"Fonsny visibility ownership identity drifted: {key}")
    if owner.get("restore_only_while_still_owned") is not True:
        fail("owner-aware visibility restore rail missing")
    if owner.get("later_owner_preserved") is not True:
        fail("later visibility owner preservation rail missing")
    if owner.get("bookkeeping_cleared_on_teardown") is not True:
        fail("visibility bookkeeping teardown rail missing")

    source = RUNTIME_PATH.read_text(encoding="utf-8")
    for literal in (
        'VISIBILITY_OWNER_META := "fonsny_visibility_owner"',
        'VISIBILITY_OWNER_VALUE := "midi_fonsny_full_entrance_runtime"',
        'REPLACEMENT_NAME := "EntranceSourceBackedFonsnyPorch"',
        "var _original_visibility: Dictionary = {}",
    ):
        if literal not in source:
            fail(f"Fonsny visibility ownership runtime identity missing: {literal}")

    collect = function_body(source, "_collect_and_validate_superseded")
    release = function_body(source, "_release_superseded_visibility_ownership")
    exit_body = function_body(source, "_exit_tree")
    owned_release = function_body(source, "_release_owned_replacement")
    if not collect or "_original_visibility" not in collect or ".visible" not in collect:
        fail("baseline visibility is not captured before Fonsny replacement")
    if not release:
        fail("Fonsny visibility cleanup helper missing")
    for token in ("VISIBILITY_OWNER_META", "VISIBILITY_OWNER_VALUE", "_original_visibility", ".visible"):
        if token not in release:
            fail(f"owner-aware visibility restore incomplete: {token}")
    if "erase_meta" not in release and "remove_meta" not in release:
        fail("Fonsny visibility ownership metadata is not cleared")
    if "_release_owned_replacement()" not in exit_body:
        fail("Fonsny owned replacement cleanup not called from _exit_tree")
    if "_release_superseded_visibility_ownership()" not in owned_release:
        fail("owned replacement teardown does not restore visibility ownership")
    if "_original_visibility.clear()" not in owned_release:
        fail("Fonsny visibility bookkeeping not cleared synchronously")

    # Fail closed if teardown goes back to an unconditional visibility reset.
    if re.search(r"\.visible\s*=\s*true", release):
        fail("unconditional visibility reset reintroduced at Fonsny teardown")

    print("SHARED_ENVIRONMENT_VISIBILITY_OWNERSHIP_OK owners=1 owner=fonsny")


if __name__ == "__main__":
    main()
