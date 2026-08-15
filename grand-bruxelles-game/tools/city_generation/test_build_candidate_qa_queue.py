#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_candidate_qa_queue.py'); s=importlib.util.spec_from_file_location('q',p); q=importlib.util.module_from_spec(s); s.loader.exec_module(q)
payload={'format':'grand-bruxelles-mass-candidate-manifest-v1','buildings':[
 {'building_id':'A','cell_id':'c1','state':'READY_FOR_QA','vertex_count':5,'area_m2':20,'recipe_digest':'r','candidate_digest':'a'},
 {'building_id':'B','cell_id':'c1','state':'QUARANTINE','vertex_count':5,'area_m2':10,'reasons':['missing'],'candidate_digest':'b'},
 {'building_id':'C','cell_id':'c1','state':'QUARANTINE','vertex_count':5,'area_m2':10,'reasons':['missing'],'candidate_digest':'c'},
 {'building_id':'D','cell_id':'c2','state':'READY_FOR_QA','vertex_count':3,'area_m2':10,'recipe_digest':'r','candidate_digest':'d'}]}
x=q.build(payload,1); y=q.build(payload,1); assert x==y
assert x['summary']=={'authoritative_buildings':4,'mandatory_ready':2,'mandatory_preflight_failures':1,'quarantine_sampled':1,'cells':2,'queue_items':3}
assert x['queue'][0]['building_id']=='A' and x['queue'][0]['preflight']=='PASS'
assert x['queue'][1]['building_id']=='D' and x['queue'][1]['preflight']=='FAIL'
assert x['runtime_promotion_allowed'] is False and x['status']=='PRE_VISUAL_QA_ONLY'
print('CANDIDATE_QA_QUEUE_GUARDRAILS_OK deterministic=true mandatory_all_ready=true fail_closed=true')
