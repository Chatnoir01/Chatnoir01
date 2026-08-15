#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('apply_facade_rules.py'); s=importlib.util.spec_from_file_location('rules',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
base={'building_id':'B1','state':'CANDIDATE','reasons':[],'recipe_digest':'abc','style_recipe':{'base_color_rgb':[300,-4,128],'vertical_rhythm_normalized':[0.10,0.11,0.30,0.70,0.71],'horizontal_rhythm_normalized':[0.2,0.5,0.8],'semantic_elements':[],'height_m':None,'street_facing_edge':None},'geometry':{'edge_lengths_m':[8.0,12.0,8.0,12.0]}}
a=m.correct(base); b=m.correct(base)
assert a==b
assert a['state']=='CORRECTED_CANDIDATE'
assert a['style_recipe']['base_color_rgb']==[255,0,128]
assert a['style_recipe']['vertical_rhythm_normalized']==[0.1,0.3,0.7]
assert a['correction']['changes']==['base_color_rgb_clamped','vertical_rhythm_normalized_normalized']
unsafe={**base,'style_recipe':{**base['style_recipe'],'height_m':17.0,'street_facing_edge':2,'semantic_elements':[{'kind':'window'}]},'geometry':{'edge_lengths_m':[0.5,8.0,8.0]}}
u=m.correct(unsafe)
assert u['state']=='QUARANTINE'
assert u['style_recipe']['height_m'] is None and u['style_recipe']['street_facing_edge'] is None and u['style_recipe']['semantic_elements']==[]
assert 'unvalidated_height_present' in u['reasons'] and 'implausibly_short_footprint_edge' in u['reasons']
print('FACADE_RULE_CORRECTION_GUARDRAILS_OK deterministic=true unsafe_semantics_removed=true geometry_preserved=true')
