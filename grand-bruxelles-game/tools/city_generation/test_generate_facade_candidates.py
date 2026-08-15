#!/usr/bin/env python3
import importlib.util, tempfile, json
from pathlib import Path
p=Path(__file__).with_name('generate_facade_candidates.py'); s=importlib.util.spec_from_file_location('g',p); g=importlib.util.module_from_spec(s); s.loader.exec_module(g)
ready={'building_id':'B','status':'READY','visual_confidence':.9,'view_count':3,'independent_source_count':2,'reference_ids':['1','2','3'],'palette_consensus':[{'rgb':[160,140,120],'weight_fraction':1.0}],'vertical_band_consensus':[{'position':.2},{'position':.5},{'position':.8}],'horizontal_band_consensus':[{'position':.25},{'position':.5},{'position':.75}],'measured_consensus':{'mean_luminance':{'value':120},'vertical_edge_density':{'value':.2},'horizontal_edge_density':{'value':.18}}}
geom={'building_id':'B','cell_id':'c','area_m2':100,'footprint_31370':[[100,100],[110,100],[110,110],[100,110],[100,100]],'footprint_digest':'abc'}
r=g.recipe_for(ready,geom)
assert r['state']=='CANDIDATE' and r['style_recipe']['height_m'] is None and r['style_recipe']['street_facing_edge'] is None and r['style_recipe']['semantic_elements']==[]
assert r['style_recipe']['vertical_rhythm_normalized']==[.2,.5,.8]
assert r['geometry']['edge_lengths_m']==[10.0,10.0,10.0,10.0]
blocked=dict(ready); blocked['status']='CONFLICT'; rb=g.recipe_for(blocked,geom); assert rb['state']=='QUARANTINE' and 'visual_consensus_not_ready' in rb['reasons']
missing=g.recipe_for(ready,None); assert missing['state']=='QUARANTINE' and 'urbis_building_geometry_missing' in missing['reasons']
a=g.generate({'buildings':[ready]}, {'B':geom}); b=g.generate({'buildings':[ready]}, {'B':geom}); assert a==b
print('FACADE_CANDIDATE_GUARDRAILS_OK deterministic=true no_height_invention=true no_front_edge_invention=true no_semantic_invention=true')
