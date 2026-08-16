#!/usr/bin/env python3
import importlib.util, json, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('collect_manual_frontier_reviews', HERE/'collect_manual_frontier_reviews.py')
mod=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(mod)

def heights(cell, candidate=False):
    buildings=[]
    if candidate:
        buildings=[{"building_id":"building-a","candidate_height_m":18.2,"confidence":"high","runtime_approved":False,"secondary_validation_required":True,"height_stats":{"review_flags":[]}}]
    return {"format":"grand-bruxelles-cell-building-height-candidates-v1","cell_id":cell,"crs":"EPSG:31370","candidate_count":len(buildings),"runtime_approved_count":0,"runtime_promotion_allowed":False,"buildings":buildings,"candidate_digest":"h"}
def terrain(cell):
    return {"format":"grand-bruxelles-cell-dtm-lod-evidence-v1","cell_id":cell,"crs":"EPSG:31370","runtime_approved":False,"selection":{"selected_resolution_m":2.0,"selected_p95_abs_error_m":0.1,"runtime_approved":False,"remaining_runtime_gates":["seams"],"blockers":[]},"evidence_digest":"t"}
def secondary(cell):
    return {"schema":"grand-bruxelles-ixelles-semantic-dsm-comparison-v1","cell":cell,"source_crs":"EPSG:31370","policy":{"runtime_approval":False},"records":[{"building_id":"building-a","semantic_height_m":17.4,"semantic_match_score":0.97,"semantic_match_margin":0.42,"dsm_confidence":"high","dsm_policy_candidate_m":18.2,"abs_delta_m":0.8,"agreement":"strong","strong_validation_candidate":True,"runtime_approved":False}],"runtime_approved":False}

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)/'cells'; out=Path(tmp)/'reviews'; root.mkdir()
    ready=root/'ready'; ready.mkdir(); (ready/'building_height_candidates.json').write_text(json.dumps(heights('ready'))); (ready/'terrain_lod_evidence.json').write_text(json.dumps(terrain('ready')))
    validated=root/'validated'; validated.mkdir(); (validated/'building_height_candidates.json').write_text(json.dumps(heights('validated',True))); (validated/'terrain_lod_evidence.json').write_text(json.dumps(terrain('validated'))); (validated/'secondary_height_evidence.json').write_text(json.dumps(secondary('validated')))
    pending=root/'pending'; pending.mkdir(); (pending/'building_height_candidates.json').write_text(json.dumps(heights('pending')))
    report=mod.collect(root,out)
    assert report['ready_count']==2 and report['pending_count']==1, report
    assert report['secondary_validated_count']==1, report
    assert report['secondary_pending_count']==0, report
    assert report['secondary_blocked_count']==0, report
    assert report['secondary_validated_cells']==['validated'], report
    assert (out/'ready.json').exists() and (out/'validated.json').exists() and not (out/'pending.json').exists()
    assert (out/'validated.secondary.json').exists()
    review=json.loads((out/'ready.json').read_text())
    validation=json.loads((out/'validated.secondary.json').read_text())
    assert review['runtime_promotion_allowed'] is False
    assert validation['secondary_validation_complete'] is True
    assert validation['validated_candidate_count']==1
    assert validation['runtime_promotion_allowed'] is False
print('CITYGEN_BATCH_MANUAL_FRONTIER_REVIEWS_OK ready=2 pending=1 secondary_validated=1 fail_closed=true')
