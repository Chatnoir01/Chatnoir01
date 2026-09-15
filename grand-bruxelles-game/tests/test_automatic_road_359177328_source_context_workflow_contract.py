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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_WORKFLOW_CONTRACT_FAIL: {message}")


def main() -> int:
    script = SCRIPT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    require(EXPECTED_MARKER in script and EXPECTED_MARKER in workflow, "diagnostic marker missing")
    require("SOURCE_CONTEXT_COMPILE_CONTAMINATION_FAIL" in workflow, "compile contamination guard missing")
    require("SOURCE_CONTEXT_IMPORT_CONTAMINATION_FAIL" in workflow, "import contamination guard missing")
    require("--headless --editor --path . --quit 2>&1" in workflow, "natural editor import missing")
    require("--quit-after" not in workflow, "timed import is forbidden")
    for marker in ("SCRIPT ERROR: Parse Error:", "SCRIPT ERROR: Compile Error:", "ERROR: Failed to load script"):
        require(workflow.count(marker) >= 2, f"error marker not guarded twice: {marker}")
    # Both pull_request and workflow_dispatch must prove checkout identity and an
    # exact live-main merge base. A manual run must never bypass provenance.
    require("if: github.event_name == 'pull_request'" not in workflow, "pull-request-only provenance guard forbidden")
    require("git fetch origin main --no-tags" in workflow, "live-main fetch missing")
    require('test "$(git rev-parse HEAD)" = "${{ github.event.pull_request.head.sha || github.sha }}"' in workflow, "checked-out head identity check missing")
    require('test "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)"' in workflow, "exact live-main merge-base check missing")
    # The source diagnostic says the human REJECT remains binding. Prove that claim
    # operationally: the canonical strict veto must run and pass before Godot can
    # perform any source-context measurement.
    require(VETO_TEST in workflow, "canonical human veto invocation missing")
    require(workflow.index(VETO_TEST) < workflow.index(MEASURE_STEP), "human veto must precede Godot measurement")
    require("automatic_road_359177328_human_review.json" in workflow, "human review receipt path trigger missing")
    require("test_automatic_road_359177328_human_review_veto.py" in workflow, "human veto test path trigger missing")
    require("func _classify_source_context(left_hits: int, right_hits: int, coverage_clamped: bool) -> Dictionary:" in script, "source classifier missing")
    require("func _verify_classification_truth_table() -> bool:" in script and TABLE_MARKER in script, "classification truth table missing")
    require("source_coverage_insufficient_for_visual_void_claim" in script, "clamped-coverage fail-closed classification missing")
    require("bilateral_source_context_present_within_covered_radius" in script, "covered-radius bilateral classification missing")
    require("human_visual_reject_still_binding=true" in script, "binding human reject marker missing")
    require("destination_advertisable=false" in script and "visual_acceptance=false" in script and "jouable=false" in script, "closed promotion rails missing")
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_WORKFLOW_CONTRACT_GREEN optimization_safe=true")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
