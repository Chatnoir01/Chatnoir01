from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VISIBILITY_CONTRACT = ROOT / "data" / "qa" / "shared_environment_visibility_ownership_contract.json"
VISIBILITY_TEST = ROOT / "game" / "tests" / "shared_environment_visibility_ownership_contract_test.py"
LIFECYCLE_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-shared-environment-lifecycle-contract.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not VISIBILITY_CONTRACT.is_file():
        fail("shared Environment visibility ownership contract missing from lifecycle bridge")
    if not VISIBILITY_TEST.is_file():
        fail("shared Environment visibility ownership validator missing from lifecycle bridge")
    if not LIFECYCLE_WORKFLOW.is_file():
        fail("shared Environment lifecycle workflow missing")

    contract = json.loads(VISIBILITY_CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-shared-environment-visibility-ownership-v1":
        fail("visibility ownership schema drifted")
    if contract.get("central_lifecycle_gate_required") is not True:
        fail("visibility ownership is not fail-closed from the central lifecycle gate")
    if contract.get("visibility_ownership_registry_expected_count") != 1:
        fail("central lifecycle bridge visibility-owner count drifted")
    if contract.get("normal_player_visual_change_authorized") is not False:
        fail("central lifecycle bridge must not authorize visibility art changes")

    workflow = LIFECYCLE_WORKFLOW.read_text(encoding="utf-8")
    for watched_path in (
        "grand-bruxelles-game/data/qa/shared_environment_visibility_ownership_contract.json",
        "grand-bruxelles-game/game/tests/shared_environment_visibility_ownership_contract_test.py",
        "grand-bruxelles-game/game/tests/shared_environment_visibility_lifecycle_bridge_test.py",
    ):
        if watched_path not in workflow:
            fail(f"central lifecycle workflow does not watch visibility ownership evidence: {watched_path}")
    for command in (
        "python3 grand-bruxelles-game/game/tests/shared_environment_visibility_ownership_contract_test.py",
        "python3 grand-bruxelles-game/game/tests/shared_environment_visibility_lifecycle_bridge_test.py",
    ):
        if command not in workflow:
            fail(f"central lifecycle workflow does not execute visibility ownership rail: {command}")

    print("SHARED_ENVIRONMENT_VISIBILITY_LIFECYCLE_BRIDGE_OK owners=1 central_gate=true")


if __name__ == "__main__":
    main()
