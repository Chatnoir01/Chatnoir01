from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNED_CHILD_CONTRACT = ROOT / "data" / "qa" / "shared_environment_owned_child_runtime_lifecycle_contract.json"
OWNED_CHILD_TEST = ROOT / "game" / "tests" / "shared_environment_owned_child_runtime_lifecycle_test.py"
LIFECYCLE_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-shared-environment-lifecycle-contract.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not OWNED_CHILD_CONTRACT.is_file():
        fail("shared Environment owned-child contract missing from lifecycle bridge")
    if not OWNED_CHILD_TEST.is_file():
        fail("shared Environment owned-child validator missing from lifecycle bridge")
    if not LIFECYCLE_WORKFLOW.is_file():
        fail("shared Environment lifecycle workflow missing")

    contract = json.loads(OWNED_CHILD_CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-shared-environment-owned-child-runtime-lifecycle-v1":
        fail("owned-child lifecycle schema drifted")
    if contract.get("central_lifecycle_gate_required") is not True:
        fail("owned-child lifecycle is not fail-closed from the central lifecycle gate")
    if contract.get("registered_owned_child_runtime_count") != 1:
        fail("central lifecycle bridge owned-child count drifted")
    if contract.get("geometry_or_material_change_authorized") is not False:
        fail("central lifecycle bridge must not authorize geometry or material changes")

    workflow = LIFECYCLE_WORKFLOW.read_text(encoding="utf-8")
    for watched_path in (
        "grand-bruxelles-game/data/qa/shared_environment_owned_child_runtime_lifecycle_contract.json",
        "grand-bruxelles-game/game/tests/shared_environment_owned_child_runtime_lifecycle_test.py",
        "grand-bruxelles-game/game/tests/shared_environment_owned_child_lifecycle_bridge_test.py",
    ):
        if watched_path not in workflow:
            fail(f"central lifecycle workflow does not watch owned-child lifecycle evidence: {watched_path}")
    for command in (
        "python3 grand-bruxelles-game/game/tests/shared_environment_owned_child_runtime_lifecycle_test.py",
        "python3 grand-bruxelles-game/game/tests/shared_environment_owned_child_lifecycle_bridge_test.py",
    ):
        if command not in workflow:
            fail(f"central lifecycle workflow does not execute owned-child lifecycle rail: {command}")

    print("SHARED_ENVIRONMENT_OWNED_CHILD_LIFECYCLE_BRIDGE_OK children=1 central_gate=true")


if __name__ == "__main__":
    main()
