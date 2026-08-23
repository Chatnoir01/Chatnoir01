#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-citygen-source-repair-frontier.yml"
RUNTIME_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-runtime-candidate-frontier.yml"

text = WORKFLOW.read_text(encoding="utf-8")
runtime_text = RUNTIME_WORKFLOW.read_text(encoding="utf-8")

required = (
    'group: grand-bruxelles-autonomous-citygen',
    '--batch-size 32',
    'materialize_urbis_source_cell.py',
    'repair_failures.tsv',
    'repair_success.txt',
    'git switch -C citygen-autonomous-state refs/remotes/origin/citygen-autonomous-state',
    '--force-with-lease="refs/heads/citygen-autonomous-state:${REMOTE_SHA}"',
    'id: persist',
    'durable_progress: ${{ steps.persist.outputs.durable_progress }}',
    'durable_progress=true',
    'CITYGEN_SOURCE_REPAIR_PARTIAL',
    'persisted_successes=true',
    'dispatch-regional-citygen:',
    'needs: repair-frontier',
    "needs.repair-frontier.outputs.durable_progress == 'true'",
    'grand-bruxelles-runtime-candidate-frontier.yml/dispatches',
    'CITYGEN_RUNTIME_FRONTIER_DISPATCH_OK durable_progress=true limit=32',
    'grand-bruxelles-autonomous-citygen.yml/dispatches',
    "inputs[batch_size]=32",
    'CITYGEN_SOURCE_REPAIR_CHAIN_OK durable_progress=true next=runtime_frontier+autonomous_citygen batch=32',
    'promotion_bypass=false',
)
for marker in required:
    assert marker in text, marker

persist_at = text.index('Persist repaired sources and refreshed state immediately')
surface_at = text.index('Surface repair failures after durable progress')
runtime_dispatch_at = text.index('grand-bruxelles-runtime-candidate-frontier.yml/dispatches')
regional_dispatch_at = text.index('grand-bruxelles-autonomous-citygen.yml/dispatches')
assert persist_at < surface_at < runtime_dispatch_at < regional_dispatch_at, (
    'source repair must persist first, then dispatch runtime candidates before the longer regional pass'
)
assert 'workflow_dispatch:' in runtime_text, 'runtime candidate frontier must remain explicitly dispatchable'
assert '--limit 32' in runtime_text, 'runtime candidate frontier must keep the governed 32-cell limit'
assert 'runtime_mount_authorized' in runtime_text and 'jouable_promotion_authorized' in runtime_text

assert 'runtime_mount_authorized=true' not in text
assert 'jouable_promotion_authorized=true' not in text
assert 'git push --force origin citygen-autonomous-state' not in text

print('CITYGEN_SOURCE_REPAIR_FRONTIER_CONTRACT_OK batch=32 serialized_writer=true partial_persistence=true explicit_lease=true runtime_frontier_immediate=true chained_after_durable_progress=true promotion_bypass=false')
