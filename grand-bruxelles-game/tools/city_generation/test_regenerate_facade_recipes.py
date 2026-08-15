#!/usr/bin/env python3
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('regen',HERE/'regenerate_facade_recipes.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
base={'format':'grand-bruxelles-facade-candidate-recipes-v1','recipes':[{'building_id':'B1','state':'CANDIDATE','reasons':[],'recipe_digest':'src1','geometry':{'footprint_digest':'f1','edge_lengths_m':[8.0,12.0,8.0,12.0]},'style_recipe':{'base_color_rgb':[120,130,140],'vertical_rhythm_normalized':[0.1,0.12,0.4,0.8],'horizontal_rhythm_normalized':[0.2,0.6],'semantic_elements':[],'height_m':None,'street_facing_edge':None}}]}
a=m.regenerate(base); b=m.regenerate(base)
assert a==b
assert a['summary']=={'recipes':1,'runtime_qa_ready':1,'quarantined':0}
assert a['recipes'][0]['geometry_digest']==m.geometry_digest(base['recipes'][0])
assert a['recipes'][0]['style_recipe']['vertical_rhythm_normalized']==[0.1,0.4,0.8]
assert a['recipes'][0]['state']=='REGEN_READY_FOR_RUNTIME_QA'
print('FACADE_REGENERATION_GUARDRAILS_OK deterministic=true geometry_immutable=true runtime_qa_ready=1')
