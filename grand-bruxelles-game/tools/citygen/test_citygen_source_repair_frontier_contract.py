#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-citygen-source-repair-frontier.yml"

text = WORKFLOW.read_text(encoding="utf-8")

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
    'grand-bruxelles-autonomous-citygen.yml/dispatches',
    "inputs[batch_size]=32",
    'CITYGEN_SOURCE_REPAIR_CHAIN_OK durable_progress=true next=autonomous_citygen batch=32',
    'promotion_bypass=false',
)
for marker in required:
    assert marker in text, marker

persist_at = text.index('Persist repaired sources and refreshed state immediately')
surface_at = text.index('Surface repair failures after durable progress')
dispatch_at = text.index('Dispatch governed regional CityGen after durable source repair')
assert persist_at < surface_at < dispatch_at, 'repair must persist and surface its result before the regional dispatch job'

assert 'runtime_mount_authorized=true' not in text
assert 'jouable_promotion_authorized=true' not in text
assert 'git push --force origin citygen-autonomous-state' not in text

print('CITYGEN_SOURCE_REPAIR_FRONTIER_CONTRACT_OK batch=32 serialized_writer=true partial_persistence=true explicit_lease=true chained_after_durable_progress=true promotion_bypass=false')
