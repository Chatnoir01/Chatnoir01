#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-autonomous-citygen.yml"
GRID_BUILDER = HERE / "build_brussels_regional_grid.py"

workflow = WORKFLOW.read_text(encoding="utf-8")
grid_builder = GRID_BUILDER.read_text(encoding="utf-8")

assert "EXPECTED_MUNICIPALITIES = 19" in grid_builder, "regional grid must stay locked to all 19 Brussels municipalities"
assert 'cron: "17 */2 * * *"' in workflow, "regional construction must run every two hours"
assert 'default: "32"' in workflow, "manual/default regional batch must use the scheduler maximum"
assert 'BATCH="${INPUT_BATCH_SIZE:-32}"' in workflow, "non-dispatch runs must also advance 32 cells"
assert "  push:\n    branches: [\"main\"]" in workflow, "merging the accelerator must trigger construction immediately"
assert "timeout-minutes: 120" in workflow, "expanded regional passes need enough runtime headroom"
assert "REGIONAL_MUNICIPALITY_COVERAGE_OK municipalities=19" in workflow, "workflow must prove the official grid covers 19 municipalities before mutation"

print("REGIONAL_ACCELERATION_CONTRACT_OK municipalities=19 batch=32 cadence=2h immediate_push=true")
