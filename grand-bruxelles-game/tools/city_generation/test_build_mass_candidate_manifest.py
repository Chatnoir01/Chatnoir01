#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_mass_candidate_manifest.py'); s=importlib.util.spec_from_file_location('m',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
b={'B':{'building_id':'B','cell_id':'c','area_m2':10,'vertex_count':5},'A':{'building_id':'A','cell_id':'c','area_m2':20,'vertex_count':6}}
r={'A':{'building_id':'A','state':'CANDIDATE','recipe_digest':'abc','reasons':[]},'B':{'building_id':'B','state':'QUARANTINE','recipe_digest':'def','reasons':['visual_consensus_not_ready']}}
x=m.build(b,r); y=m.build(b,r)
assert x==y
assert [q['building_id'] for q in x['buildings']]==['A','B']
assert x['summary']=={'authoritative_buildings':2,'ready_for_qa':1,'quarantined':1,'orphan_recipes':0,'total_vertices':11}
assert x['buildings'][0]['state']=='READY_FOR_QA'
assert x['buildings'][1]['state']=='QUARANTINE' and 'visual_consensus_not_ready' in x['buildings'][1]['reasons']
z=m.build(b,{'X':{'building_id':'X','state':'CANDIDATE','recipe_digest':'x'}}); assert z['summary']['orphan_recipes']==1 and z['orphan_recipe_ids']==['X']
print('MASS_CANDIDATE_GUARDRAILS_OK deterministic=true fail_closed=true orphan_detection=true')
