#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
ACCELERATOR = REPO_ROOT / ".github/workflows/grand-bruxelles-19-municipalities-accelerator.yml"
BASE_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-autonomous-citygen.yml"
GRID_BUILDER = HERE / "build_brussels_regional_grid.py"
CITYGEN = HERE / "autonomous_citygen.py"

accelerator = ACCELERATOR.read_text(encoding="utf-8")
base_workflow = BASE_WORKFLOW.read_text(encoding="utf-8")
grid_builder = GRID_BUILDER.read_text(encoding="utf-8")
citygen = CITYGEN.read_text(encoding="utf-8")

assert "EXPECTED_MUNICIPALITIES = 19" in grid_builder, "regional grid must stay locked to all 19 Brussels municipalities"
assert 'cron: "17 */2 * * *"' in accelerator, "regional accelerator must run every two hours"
assert "actions: write" in accelerator, "accelerator needs permission to dispatch the existing CityGen workflow"
assert "  push:\n    branches: [\"main\"]" in accelerator, "merge to main must trigger the first regional pass immediately"
assert "grand-bruxelles-autonomous-citygen.yml/dispatches" in accelerator, "accelerator must dispatch the governed CityGen workflow"
assert "inputs[batch_size]=32" in accelerator, "accelerator must use the scheduler maximum batch"
assert "REGIONAL_MUNICIPALITY_TARGET_OK municipalities=19 batch=32" in accelerator, "accelerator must expose its 19-municipality contract"
assert "workflow_dispatch:" in base_workflow, "governed CityGen workflow must remain dispatchable"
assert "args.batch_size < 1 or args.batch_size > 32" in citygen, "batch 32 must remain inside the scheduler's validated limit"
assert '"runtime_promotion": "forbidden_without_full_regional_maturity_contract"' in citygen, "regional acceleration must not bypass promotion gates"

print("REGIONAL_ACCELERATION_CONTRACT_OK municipalities=19 batch=32 cadence=2h immediate_push=true promotion_bypass=false")
