#!/usr/bin/env python3
from pathlib import Path

WORKFLOW = Path('.github/workflows/grand-bruxelles-citygen-source-repair-fanout-v2.yml')
text = WORKFLOW.read_text(encoding='utf-8')

required = [
    'batch_size: 128',
    'max-parallel: 16',
    'strategy:',
    'matrix:',
    'worker: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]',
    'actions/upload-artifact@v4',
    'actions/download-artifact@v4',
    'group: grand-bruxelles-autonomous-citygen',
    'cancel-in-progress: false',
    'force-with-lease',
    'runtime_mount_authorized=false',
    'jouable_promotion_authorized=false',
]
for token in required:
    assert token in text, f'missing fanout-v2 contract token: {token}'

# The expensive workers must not own the durable writer lock. Only fan-in persistence may.
worker_start = text.index('  materialize-worker:')
fanin_start = text.index('  persist-fan-in:')
worker_block = text[worker_start:fanin_start]
assert 'concurrency:' not in worker_block, 'workers must run outside durable writer lock'

persist_block = text[fanin_start:]
assert 'concurrency:' in persist_block, 'fan-in writer must own durable lock'
assert 'grand-bruxelles-autonomous-citygen' in persist_block
assert 'force-with-lease' in persist_block

# No production promotion in this ingestion accelerator.
assert 'runtime_mount_authorized=true' not in text
assert 'jouable_promotion_authorized=true' not in text
print('SOURCE_REPAIR_FANOUT_V2_CONTRACT_OK batch=128 workers=16 writer=single promotion_bypass=false')
