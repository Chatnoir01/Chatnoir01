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
    'CITYGEN_SOURCE_REPAIR_PARTIAL',
    'persisted_successes=true',
    'promotion_bypass=false',
)
for marker in required:
    assert marker in text, marker

persist_at = text.index('Persist repaired sources and refreshed state immediately')
surface_at = text.index('Surface repair failures after durable progress')
assert persist_at < surface_at, 'successful repairs must persist before failures are surfaced'

assert 'runtime_mount_authorized=true' not in text
assert 'jouable_promotion_authorized=true' not in text
assert 'git push --force origin citygen-autonomous-state' not in text

print('CITYGEN_SOURCE_REPAIR_FRONTIER_CONTRACT_OK batch=32 serialized_writer=true partial_persistence=true explicit_lease=true promotion_bypass=false')
