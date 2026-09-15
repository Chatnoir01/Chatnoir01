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
PINNED_CHECKOUT = "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
GODOT_URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_SHA256 = "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"


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
    require(PINNED_CHECKOUT in workflow, "checkout action must be pinned to immutable v4.2.2 commit")
    require("actions/checkout@v4" not in workflow, "mutable checkout tag forbidden")
    require("if: github.event_name == 'pull_request'" not in workflow, "pull-request-only provenance guard forbidden")
    require("git fetch origin main --no-tags" in workflow, "live-main fetch missing")
    require('test "$(git rev-parse HEAD)" = "${{ github.event.pull_request.head.sha || github.sha }}"' in workflow, "checked-out head identity check missing")
    require('test "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)"' in workflow, "exact live-main merge-base check missing")
    require(VETO_TEST in workflow, "canonical human veto invocation missing")
    require(workflow.index(VETO_TEST) < workflow.index(MEASURE_STEP), "human veto must precede Godot measurement")
    require("automatic_road_359177328_human_review.json" in workflow, "human review receipt path trigger missing")
    require("test_automatic_road_359177328_human_review_veto.py" in workflow, "human veto test path trigger missing")
    # Godot itself is executable supply-chain input to the diagnostic. Bind the
    # acquisition to the exact official release URL and immutable archive digest,
    # and forbid weakening curl TLS or checksum verification.
    require(workflow.count(GODOT_URL) == 1, "exact official Godot 4.7.1 release URL must appear once")
    require(workflow.count(GODOT_SHA256) == 1, "exact Godot archive SHA-256 must appear once")
    require("sha256sum -c -" in workflow, "Godot archive checksum verification missing")
    require("curl --fail --location --retry 5" in workflow, "fail-closed Godot download flags missing")
    for forbidden in ("--insecure", "-k ", "--no-check-certificate", "sha256sum -c - || true"):
        require(forbidden not in workflow, f"forbidden acquisition weakening present: {forbidden}")
    require("func _classify_source_context(left_hits: int, right_hits: int, coverage_clamped: bool) -> Dictionary:" in script, "source classifier missing")
    require("func _verify_classification_truth_table() -> bool:" in script and TABLE_MARKER in script, "classification truth table missing")
    require("source_coverage_insufficient_for_visual_void_claim" in script, "clamped-coverage fail-closed classification missing")
    require("bilateral_source_context_present_within_covered_radius" in script, "covered-radius bilateral classification missing")
    require("human_visual_reject_still_binding=true" in script, "binding human reject marker missing")
    require("destination_advertisable=false" in script and "visual_acceptance=false" in script and "jouable=false" in script, "closed promotion rails missing")
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_WORKFLOW_CONTRACT_GREEN optimization_safe=true immutable_checkout=true godot_acquisition_locked=true")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
