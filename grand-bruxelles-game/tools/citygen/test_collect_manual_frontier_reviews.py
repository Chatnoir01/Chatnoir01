#!/usr/bin/env python3
import importlib.util, json, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('collect_manual_frontier_reviews', HERE/'collect_manual_frontier_reviews.py')
mod=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(mod)

def heights(cell):
    return {"format":"grand-bruxelles-cell-building-height-candidates-v1","cell_id":cell,"crs":"EPSG:31370","candidate_count":0,"runtime_approved_count":0,"runtime_promotion_allowed":False,"buildings":[],"candidate_digest":"h"}
def terrain(cell):
    return {"format":"grand-bruxelles-cell-dtm-lod-evidence-v1","cell_id":cell,"crs":"EPSG:31370","runtime_approved":False,"selection":{"selected_resolution_m":2.0,"selected_p95_abs_error_m":0.1,"runtime_approved":False,"remaining_runtime_gates":["seams"],"blockers":[]},"evidence_digest":"t"}

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)/'cells'; out=Path(tmp)/'reviews'; root.mkdir()
    ready=root/'ready'; ready.mkdir(); (ready/'building_height_candidates.json').write_text(json.dumps(heights('ready'))); (ready/'terrain_lod_evidence.json').write_text(json.dumps(terrain('ready')))
    pending=root/'pending'; pending.mkdir(); (pending/'building_height_candidates.json').write_text(json.dumps(heights('pending')))
    report=mod.collect(root,out)
    assert report['ready_count']==1 and report['pending_count']==1, report
    assert (out/'ready.json').exists() and not (out/'pending.json').exists()
    review=json.loads((out/'ready.json').read_text())
    assert review['runtime_promotion_allowed'] is False

repo_root=HERE.parents[2]
workflow=repo_root/'.github/workflows/grand-bruxelles-citygen-manual-frontier-durable.yml'
assert workflow.exists(), 'durable manual-frontier workflow is missing'
text=workflow.read_text(encoding='utf-8')
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
print('CITYGEN_BATCH_MANUAL_FRONTIER_REVIEWS_OK ready=1 pending=1 durable_queue=true fail_closed=true')
