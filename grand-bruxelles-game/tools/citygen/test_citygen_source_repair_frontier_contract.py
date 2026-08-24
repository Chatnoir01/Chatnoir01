#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-citygen-source-repair-frontier.yml"
RUNTIME_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-runtime-candidate-frontier.yml"
SELECTOR = HERE / "build_source_repair_worklist.py"

text = WORKFLOW.read_text(encoding="utf-8")
runtime_text = RUNTIME_WORKFLOW.read_text(encoding="utf-8")
selector_text = SELECTOR.read_text(encoding="utf-8")

required = (
    'SOURCE_REPAIR_FRONTIER_LIMIT: "128"',
    'SOURCE_REPAIR_SHARDS: "16"',
    'build_source_repair_worklist.py',
    '--limit "$SOURCE_REPAIR_FRONTIER_LIMIT"',
    '--shards "$SOURCE_REPAIR_SHARDS"',
    'select-frontier:',
    'repair-shards:',
    'max-parallel: 16',
    'shard: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]',
    'actions/upload-artifact@v4',
    'actions/download-artifact@v4',
    'writer_lock=not_held',
    'repair-frontier:',
    'group: grand-bruxelles-autonomous-citygen',
    'Recover latest durable state under writer lock',
    'Merge fan-out results and reconcile attempts against latest state',
    'stale_selection_safe=true',
    'source_repair_wave_report.json',
    '--force-with-lease="refs/heads/citygen-autonomous-state:${REMOTE_SHA}"',
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
    'CITYGEN_SOURCE_REPAIR_CHAIN_OK durable_progress=true source_frontier=128 fanout=16 next=runtime_frontier+autonomous_citygen batch=32',
    'promotion_bypass=false',
)
for marker in required:
    assert marker in text, marker

select_at = text.index('select-frontier:')
shards_at = text.index('repair-shards:')
writer_at = text.index('repair-frontier:')
lock_at = text.index('group: grand-bruxelles-autonomous-citygen')
materialize_at = text.index('Rematerialize assigned authoritative UrbIS sources')
persist_at = text.index('Persist merged repairs with explicit lease')
surface_at = text.index('Surface repair failures after durable successes')
runtime_dispatch_at = text.index('grand-bruxelles-runtime-candidate-frontier.yml/dispatches')
regional_dispatch_at = text.index('grand-bruxelles-autonomous-citygen.yml/dispatches')

assert select_at < shards_at < materialize_at < writer_at < lock_at < persist_at < surface_at < runtime_dispatch_at < regional_dispatch_at
assert text.count('group: grand-bruxelles-autonomous-citygen') == 1, "only the short writer may own the durable-state lock"
assert 'workflow_dispatch:' in runtime_text, 'runtime candidate frontier must remain explicitly dispatchable'
assert '--limit 32' in runtime_text, 'runtime candidate frontier must keep the governed 32-cell limit'
assert 'runtime_mount_authorized' in runtime_text and 'jouable_promotion_authorized' in runtime_text

assert 'MAX_FRONTIER = 128' in selector_text
assert 'MAX_SHARDS = 16' in selector_text
assert '"runtime_mount_authorized": False' in selector_text
assert '"jouable_promotion_authorized": False' in selector_text

assert 'runtime_mount_authorized=true' not in text
assert 'jouable_promotion_authorized=true' not in text
assert 'git push --force origin citygen-autonomous-state' not in text

print(
    'CITYGEN_SOURCE_REPAIR_FRONTIER_CONTRACT_OK '
    'frontier=128 fanout=16 compute_outside_lock=true single_writer=true '
    'partial_persistence=true explicit_lease=true runtime_frontier_immediate=true '
    'chained_citygen_batch=32 stale_selection_safe=true promotion_bypass=false'
)
