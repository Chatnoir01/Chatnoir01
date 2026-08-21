#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
workflow = ROOT / ".github/workflows/grand-bruxelles-terrain-candidate-factory.yml"
text = workflow.read_text(encoding="utf-8")

required = [
    'name: Grand Bruxelles Terrain Candidate Factory',
    'workflows: ["Grand Bruxelles Secondary Height Factory"]',
    'group: grand-bruxelles-autonomous-citygen',
    'git fetch origin citygen-autonomous-state:refs/remotes/origin/citygen-autonomous-state',
    'git switch -C citygen-autonomous-state origin/citygen-autonomous-state',
    'terrain_runtime_authorized\':False',
    'runtime_geometry_authorized\':False',
    'collision_authorized\':False',
    'navigation_authorized\':False',
    'runtime_mount_authorized\':False',
    'production_discovery_eligible\':False',
    'automatic_production_mutation\':False',
    'unvalidated_height_fallback_allowed\':False',
]
for needle in required:
    assert needle in text, needle

# The factory may checkout main to obtain tooling after merge, but durable writes must
# always switch to the isolated CityGen state branch before staging/pushing evidence.
persist = text.split('- name: Persist terrain candidates off main', 1)[1]
assert 'git switch -C citygen-autonomous-state origin/citygen-autonomous-state' in persist
assert 'git add -- grand-bruxelles-game/data/qa/autonomous_sources' in persist
assert 'git push --force-with-lease origin citygen-autonomous-state' in persist
assert 'git push origin main' not in text
assert 'git push --force origin main' not in text
assert 'runtime_mount_authorized\':True' not in text
assert 'collision_authorized\':True' not in text
assert 'terrain_runtime_authorized\':True' not in text
assert 'production_discovery_eligible\':True' not in text

print(
    'TERRAIN_CANDIDATE_FACTORY_WIRING_OK',
    'durable_state_only=true',
    'serialized_writer=true',
    'no_main_push=true',
    'runtime_mount=false',
    'collision=false',
)
