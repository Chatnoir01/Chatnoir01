#!/usr/bin/env python3
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
REPO = PROJECT.parent
WORKFLOW = REPO / ".github" / "workflows" / "grand-bruxelles-automatic-road-player-witness.yml"
SOURCE_CONTEXT_TEST = "grand-bruxelles-game/game/tests/automatic_road_359177328_source_context_balance_test.gd"
SOURCE_CONTEXT_CONTRACT = "grand-bruxelles-game/tests/test_automatic_road_359177328_source_context_workflow_contract.py"
HUMAN_REVIEW = "grand-bruxelles-game/data/qa/corridor/automatic_road_359177328_human_review.json"
HUMAN_REVIEW_TEST = "grand-bruxelles-game/tests/test_automatic_road_359177328_human_review_veto.py"
SELF = "grand-bruxelles-game/tests/test_automatic_road_player_witness_workflow_contract.py"
GODOT_SHA256 = "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"
HUMAN_VETO_MARKER = "AUTOMATIC_ROAD_359177328_HUMAN_VETO_BOUND"
STRICT_VETO_COMMAND = "python3 tests/test_automatic_road_359177328_human_review_veto.py"


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    for required_path in (SOURCE_CONTEXT_TEST, SOURCE_CONTEXT_CONTRACT, HUMAN_REVIEW, HUMAN_REVIEW_TEST, SELF):
        assert required_path in workflow, f"player witness must rerun when {required_path} changes"
    assert HUMAN_VETO_MARKER in workflow, "player witness must fail closed on the canonical Lemonnier human REJECT before capture"
    assert STRICT_VETO_COMMAND in workflow, "player witness must execute the dependency-free closed-schema human-review veto before capture"
    assert "python3 -m pytest -q tests/test_automatic_road_359177328_human_review_veto.py" not in workflow, "pre-capture veto must not depend on runner-provided pytest"
    contract_pos = workflow.index(STRICT_VETO_COMMAND)
    capture_pos = workflow.index("Capture source-backed road-359177328 player witness")
    assert contract_pos < capture_pos, "strict human veto must execute before player capture"
    assert GODOT_SHA256 in workflow, "Godot 4.7.1 player-witness binary must be SHA-256 pinned"
    assert "sha256sum -c -" in workflow, "player-witness workflow must verify the downloaded Godot archive before extraction"
    assert "--retry-all-errors" in workflow, "Godot download must tolerate transient transport failures without changing the pinned payload"
    print("AUTOMATIC_ROAD_PLAYER_WITNESS_WORKFLOW_CONTRACT_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
