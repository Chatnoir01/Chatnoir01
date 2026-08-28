from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNERSHIP_TEST = ROOT / "game" / "tests" / "brussels_osm_sidewalk_material_ownership_test.py"
LIFECYCLE_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-shared-environment-lifecycle-contract.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not OWNERSHIP_TEST.is_file():
        fail("shared sidewalk material ownership validator missing from lifecycle bridge")
    if not LIFECYCLE_WORKFLOW.is_file():
        fail("shared Environment lifecycle workflow missing")

    workflow = LIFECYCLE_WORKFLOW.read_text(encoding="utf-8")
    for watched_path in (
        "grand-bruxelles-game/game/tests/brussels_osm_sidewalk_material_ownership_test.py",
        "grand-bruxelles-game/game/tests/shared_environment_sidewalk_material_ownership_lifecycle_bridge_test.py",
    ):
        if watched_path not in workflow:
            fail(f"central lifecycle workflow does not watch sidewalk material ownership evidence: {watched_path}")

    for command in (
        "python3 grand-bruxelles-game/game/tests/brussels_osm_sidewalk_material_ownership_test.py",
        "python3 grand-bruxelles-game/game/tests/shared_environment_sidewalk_material_ownership_lifecycle_bridge_test.py",
    ):
        if command not in workflow:
            fail(f"central lifecycle workflow does not execute sidewalk material ownership rail: {command}")

    print("SHARED_ENVIRONMENT_SIDEWALK_MATERIAL_OWNERSHIP_LIFECYCLE_BRIDGE_OK central_gate=true")


if __name__ == "__main__":
    main()
