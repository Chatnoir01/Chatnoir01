#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_multiview_consensus.py'); s=importlib.util.spec_from_file_location('m',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def row(i,source,vd,hd,lum=120,bands=None,assoc=.9,quality='USABLE'):
 return {'canonical_id':str(i),'source':source,'building_candidates':[{'building_id':'B','confidence':assoc}], 'visual_analysis':{'quality_status':quality,'vertical_edge_density':vd,'horizontal_edge_density':hd,'mean_luminance':lum,'mean_channel_stddev':30,'strong_vertical_bands':bands or [.2,.5,.8],'strong_horizontal_bands':[.25,.5,.75],'palette':[{'rgb':[160,140,120],'fraction':1.0}]}}
# Two agreeing independent views plus one wild outlier must remain usable and robust.
a=[row(1,'Commons',.20,.18,118),row(2,'KartaView',.22,.19,122),row(3,'Other',.95,.90,245)]
r=m.consensus_for_building('B',a)
assert r['view_count']==3 and r['independent_source_count']==3
assert r['measured_consensus']['vertical_edge_density']['value']<.4
assert r['vertical_band_consensus'] and r['horizontal_band_consensus']
# Repeated same source is not independent evidence.
r2=m.consensus_for_building('B',[row(1,'Commons',.2,.2),row(2,'Commons',.21,.21)])
assert r2['status']=='INSUFFICIENT_EVIDENCE' and 'insufficient_independent_source_diversity' in r2['reasons']
# One view can never be READY.
r3=m.consensus_for_building('B',[row(1,'Commons',.2,.2)])
assert r3['status']=='INSUFFICIENT_EVIDENCE'
# Low association must not enter consensus at all.
out=m.build([row(1,'Commons',.2,.2,assoc=.5),row(2,'KartaView',.2,.2,assoc=.5)])
assert out['summary']['associated_records']==0 and out['summary']['skipped_low_association']==2 and out['buildings']==[]
print('MULTIVIEW_CONSENSUS_GUARDRAILS_OK multi_view=true outlier_robust=true source_diversity=true low_association_blocked=true')
