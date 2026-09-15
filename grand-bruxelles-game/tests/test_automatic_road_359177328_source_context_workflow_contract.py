#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
REPO = PROJECT.parent
SCRIPT = PROJECT / "game" / "tests" / "automatic_road_359177328_source_context_balance_test.gd"
WORKFLOW = REPO / ".github" / "workflows" / "grand-bruxelles-automatic-road-359177328-source-context-balance.yml"
EXPECTED_MARKER = "AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_DIAGNOSTIC_GREEN:"
TABLE_MARKER = "AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_CLASSIFICATION_TABLE_GREEN:"
VETO_TEST = "python3 tests/test_automatic_road_359177328_human_review_veto.py"
MEASURE_STEP = "Measure bilateral source context from production selection"

def main() -> int:
    script = SCRIPT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert EXPECTED_MARKER in script and EXPECTED_MARKER in workflow
    assert "SOURCE_CONTEXT_COMPILE_CONTAMINATION_FAIL" in workflow
    assert "SOURCE_CONTEXT_IMPORT_CONTAMINATION_FAIL" in workflow
    assert "--headless --editor --path . --quit 2>&1" in workflow
    assert "--quit-after" not in workflow
    for marker in ("SCRIPT ERROR: Parse Error:", "SCRIPT ERROR: Compile Error:", "ERROR: Failed to load script"):
        assert workflow.count(marker) >= 2
    # Both pull_request and workflow_dispatch must prove checkout identity and an
    # exact live-main merge base. A manual run must never bypass provenance.
    assert "if: github.event_name == 'pull_request'" not in workflow
    assert 'git fetch origin main --no-tags' in workflow
    assert 'test "$(git rev-parse HEAD)" = "${{ github.event.pull_request.head.sha || github.sha }}"' in workflow
    assert 'test "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)"' in workflow
    # The source diagnostic says the human REJECT remains binding. Prove that claim
    # operationally: the canonical strict veto must run and pass before Godot can
    # perform any source-context measurement.
    assert VETO_TEST in workflow
    assert workflow.index(VETO_TEST) < workflow.index(MEASURE_STEP)
    assert "automatic_road_359177328_human_review.json" in workflow
    assert "test_automatic_road_359177328_human_review_veto.py" in workflow
    assert "func _classify_source_context(left_hits: int, right_hits: int, coverage_clamped: bool) -> Dictionary:" in script
    assert "func _verify_classification_truth_table() -> bool:" in script and TABLE_MARKER in script
    assert "source_coverage_insufficient_for_visual_void_claim" in script
    assert "bilateral_source_context_present_within_covered_radius" in script
    assert "human_visual_reject_still_binding=true" in script
    assert "destination_advertisable=false" in script and "visual_acceptance=false" in script and "jouable=false" in script
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_WORKFLOW_CONTRACT_GREEN")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
