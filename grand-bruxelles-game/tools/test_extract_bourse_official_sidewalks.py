#!/usr/bin/env python3
from pathlib import Path
import importlib.util, json, tempfile
p=Path(__file__).with_name('extract_bourse_official_sidewalks.py')
s=importlib.util.spec_from_file_location('m',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
r=Path(tempfile.mkdtemp())
for i,rel in enumerate(m.SURFACE_FILES):
 q=r/rel; q.parent.mkdir(parents=True,exist_ok=True); x=100+i; y=200+i; q.write_text(json.dumps({'surfaces':[{'level':0,'source_rings_epsg31370':[[[x,y],[x+1,y],[x+1,y+1],[x,y+1],[x,y]]]}]}))
b=m._surface_bbox(r)
assert b==(92.0,192.0,113.0,213.0)
f={'type':'FeatureCollection','features':[{'id':'in','properties':{'ssft':'x'},'geometry':{'type':'Polygon','coordinates':[[[95,195],[96,195],[96,196],[95,196],[95,195]]]}},{'id':'out','geometry':{'type':'Polygon','coordinates':[[[500,500],[501,500],[501,501],[500,501],[500,500]]]}}]}
e=m.build_evidence(f,'abc',r)
assert e['selection']['feature_count']==1 and e['runtime_approved'] is False and e['curb_elevation_resolved'] is False
print('Bourse sidewalk extractor test: OK')
