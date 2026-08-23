#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
ACCELERATOR = REPO_ROOT / ".github/workflows/grand-bruxelles-19-municipalities-accelerator.yml"
BASE_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-autonomous-citygen.yml"
SOURCE_REPAIR_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-citygen-source-repair-frontier.yml"
GRID_BUILDER = HERE / "build_brussels_regional_grid.py"
CITYGEN = HERE / "autonomous_citygen.py"

accelerator = ACCELERATOR.read_text(encoding="utf-8")
base_workflow = BASE_WORKFLOW.read_text(encoding="utf-8")
source_repair_workflow = SOURCE_REPAIR_WORKFLOW.read_text(encoding="utf-8")
grid_builder = GRID_BUILDER.read_text(encoding="utf-8")
citygen = CITYGEN.read_text(encoding="utf-8")

assert "EXPECTED_MUNICIPALITIES = 19" in grid_builder, "regional grid must stay locked to all 19 Brussels municipalities"
assert 'cron: "17 */2 * * *"' in accelerator, "regional accelerator must run every two hours"
assert "actions: write" in accelerator, "accelerator needs permission to dispatch the governed source-repair workflow"
assert "  push:\n    branches: [\"main\"]" in accelerator, "merge to main must trigger the first regional pass immediately"
assert "grand-bruxelles-citygen-source-repair-frontier.yml/dispatches" in accelerator, "accelerator must explicitly dispatch the short authoritative source-repair frontier"
assert "grand-bruxelles-autonomous-citygen.yml/dispatches" not in accelerator, "accelerator must not race source repair by dispatching Autonomous CityGen directly"
assert "REGIONAL_SOURCE_REPAIR_DISPATCH_OK batch=32" in accelerator, "accelerator must expose the source-repair dispatch contract"
assert "chained_citygen=true" in accelerator, "accelerator must declare that the full regional pass is chained after durable repair"
assert "workflow_dispatch:" in source_repair_workflow, "short source-repair frontier must remain dispatchable"
assert "group: grand-bruxelles-autonomous-citygen" in source_repair_workflow, "short source repair must share the durable-writer lock"
assert "durable_progress: ${{ steps.persist.outputs.durable_progress }}" in source_repair_workflow, "source repair must expose durable progress"
assert "grand-bruxelles-autonomous-citygen.yml/dispatches" in source_repair_workflow, "source repair must chain the governed regional CityGen pass"
assert "inputs[batch_size]=32" in source_repair_workflow, "chained regional CityGen must use the scheduler maximum batch"
assert "needs.repair-frontier.outputs.durable_progress == 'true'" in source_repair_workflow, "regional CityGen dispatch must require durable source-repair progress"
assert "CITYGEN_SOURCE_REPAIR_CHAIN_OK durable_progress=true next=autonomous_citygen batch=32" in source_repair_workflow, "source repair must expose its sequential chain contract"
assert "workflow_dispatch:" in base_workflow, "governed CityGen workflow must remain dispatchable"
assert "args.batch_size < 1 or args.batch_size > 32" in citygen, "batch 32 must remain inside the scheduler's validated limit"
assert '"runtime_promotion": "forbidden_without_full_regional_maturity_contract"' in citygen, "regional acceleration must not bypass promotion gates"

print("REGIONAL_ACCELERATION_CONTRACT_OK municipalities=19 batch=32 cadence=2h immediate_push=true sequential_source_repair=true promotion_bypass=false")
