#!/usr/bin/env python3
"""Workflow regression: persist scheduler state after source/evidence mutations."""
from pathlib import Path

workflow = (Path(__file__).resolve().parents[3] / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml").read_text(encoding="utf-8")

refresh_name = "Refresh scheduler state after source and evidence mutations"
persist_name = "Persist autonomous progress off main"
assert refresh_name in workflow, "post-mutation scheduler refresh step is missing"
assert persist_name in workflow, "persistence step is missing"
assert workflow.index(refresh_name) < workflow.index(persist_name), "state refresh must happen before durable persistence"

required = [
    "--refresh-only",
    "--state /tmp/citygen-out/autonomous_citygen_state.json",
    "--target-grid /tmp/citygen-out/brussels_regional_target_grid.json",
    "--output-dir /tmp/citygen-refresh",
    "cp /tmp/citygen-refresh/autonomous_citygen_state.json /tmp/citygen-out/autonomous_citygen_state.json",
]
for token in required:
    assert token in workflow, f"missing refresh contract: {token}"

# Keep the original scheduling report/worklist as the audit of work actually chosen
# this pass; only the state snapshot should be replaced by post-mutation truth.
assert "cp /tmp/citygen-refresh/autonomous_citygen_report.json /tmp/citygen-out/autonomous_citygen_report.json" not in workflow
assert "cp /tmp/citygen-refresh/worklist.txt /tmp/citygen-out/worklist.txt" not in workflow

print("AUTONOMOUS_CITYGEN_POST_MUTATION_REFRESH_OK state_only=true audit_preserved=true")
