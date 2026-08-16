#!/usr/bin/env python3
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / '.github/workflows/grand-bruxelles-citygen-manual-frontier-durable.yml'

assert WORKFLOW.exists(), 'durable manual-frontier workflow is missing'
text = WORKFLOW.read_text(encoding='utf-8')
for required in [
    'Grand Bruxelles Autonomous CityGen',
    "head_branch == 'main'",
    'origin/citygen-autonomous-state',
    'collect_manual_frontier_reviews.py',
    'autonomous_manual_frontier_reviews',
    'runtime_promotion_allowed',
    'grand-bruxelles-autonomous-citygen',
]:
    assert required in text, f'durable manual-frontier wiring missing: {required}'

print('CITYGEN_DURABLE_MANUAL_FRONTIER_WIRING_OK fail_closed=true')
