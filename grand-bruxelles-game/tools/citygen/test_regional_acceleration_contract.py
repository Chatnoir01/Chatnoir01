#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
ACCELERATOR = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-19-municipalities-accelerator.yml"
BASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml"
SOURCE_REPAIR_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-citygen-source-repair-frontier.yml"
RUNTIME_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-runtime-candidate-frontier.yml"
GRID_BUILDER = HERE / "build_brussels_regional_grid.py"
CITYGEN = HERE / "autonomous_citygen.py"
SELECTOR = HERE / "build_source_repair_worklist.py"

accelerator = ACCELERATOR.read_text(encoding="utf-8")
base_workflow = BASE_WORKFLOW.read_text(encoding="utf-8")
source_repair_workflow = SOURCE_REPAIR_WORKFLOW.read_text(encoding="utf-8")
runtime_workflow = RUNTIME_WORKFLOW.read_text(encoding="utf-8")
grid_builder = GRID_BUILDER.read_text(encoding="utf-8")
citygen = CITYGEN.read_text(encoding="utf-8")
selector = SELECTOR.read_text(encoding="utf-8")

assert "EXPECTED_MUNICIPALITIES = 19" in grid_builder, "regional grid must stay locked to all 19 Brussels municipalities"
assert 'cron: "17 */2 * * *"' in accelerator, "regional accelerator must run every two hours"
assert "actions: write" in accelerator, "accelerator needs permission to dispatch the governed source-repair workflow"
assert "  push:\n    branches: [\"main\"]" in accelerator, "merge to main must trigger the first regional pass immediately"
assert "grand-bruxelles-citygen-source-repair-frontier.yml/dispatches" in accelerator, "accelerator must explicitly dispatch the authoritative source-repair frontier"
assert "grand-bruxelles-autonomous-citygen.yml/dispatches" not in accelerator, "accelerator must not race source repair by dispatching Autonomous CityGen directly"
assert "grand-bruxelles-runtime-candidate-frontier.yml/dispatches" not in accelerator, "accelerator must not read pre-repair state by dispatching runtime candidates directly"
assert "REGIONAL_SOURCE_REPAIR_DISPATCH_OK source_frontier=128 fanout=16 chained_citygen_batch=32 writer_lock=single" in accelerator
assert "chained_citygen=true" in accelerator, "accelerator must declare that follow-up work is chained after durable repair"

assert "workflow_dispatch:" in source_repair_workflow, "source-repair frontier must remain dispatchable"
assert 'SOURCE_REPAIR_FRONTIER_LIMIT: "128"' in source_repair_workflow
assert 'SOURCE_REPAIR_SHARDS: "16"' in source_repair_workflow
assert 'max-parallel: 16' in source_repair_workflow
assert 'build_source_repair_worklist.py' in source_repair_workflow
assert source_repair_workflow.count("group: grand-bruxelles-autonomous-citygen") == 1, "only the short durable writer may hold the shared lock"
assert source_repair_workflow.index("repair-shards:") < source_repair_workflow.index("group: grand-bruxelles-autonomous-citygen")
assert "durable_progress: ${{ steps.persist.outputs.durable_progress }}" in source_repair_workflow, "source repair must expose durable source progress"
assert "grand-bruxelles-runtime-candidate-frontier.yml/dispatches" in source_repair_workflow, "source repair must immediately chain runtime candidate compilation from repaired durable state"
assert "CITYGEN_RUNTIME_FRONTIER_DISPATCH_OK durable_progress=true limit=32" in source_repair_workflow, "runtime frontier stays governed at 32"
assert "grand-bruxelles-autonomous-citygen.yml/dispatches" in source_repair_workflow, "source repair must chain the governed regional CityGen pass"
assert "inputs[batch_size]=32" in source_repair_workflow, "chained regional CityGen must keep the scheduler's governed maximum batch"
assert "needs.repair-frontier.outputs.durable_progress == 'true'" in source_repair_workflow, "all follow-up dispatches must require durable source progress"
assert "CITYGEN_SOURCE_REPAIR_CHAIN_OK durable_progress=true source_frontier=128 fanout=16 next=runtime_frontier+autonomous_citygen batch=32" in source_repair_workflow

assert "MAX_FRONTIER = 128" in selector
assert "MAX_SHARDS = 16" in selector
assert "workflow_dispatch:" in runtime_workflow, "runtime candidate frontier must remain dispatchable"
assert "--limit 32" in runtime_workflow, "runtime candidate frontier must keep the 32-cell governed limit"
assert "workflow_dispatch:" in base_workflow, "governed CityGen workflow must remain dispatchable"
assert "args.batch_size < 1 or args.batch_size > 32" in citygen, "full CityGen batch must remain capped at 32"
assert '"runtime_promotion": "forbidden_without_full_regional_maturity_contract"' in citygen, "regional acceleration must not bypass promotion gates"

print(
    "REGIONAL_ACCELERATION_CONTRACT_OK municipalities=19 source_frontier=128 fanout=16 "
    "chained_citygen_batch=32 cadence=2h immediate_push=true single_writer=true "
    "runtime_frontier_immediate=true promotion_bypass=false"
)
