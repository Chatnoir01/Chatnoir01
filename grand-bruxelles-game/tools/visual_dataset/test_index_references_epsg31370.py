#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('index_references_epsg31370.py'); s=importlib.util.spec_from_file_location('i',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
x,y=m.TRANSFORMER.transform(4.3517,50.8503)
assert 140000 < x < 160000 and 165000 < y < 180000, (x,y)
inv=__import__('pyproj').Transformer.from_crs('EPSG:31370','EPSG:4326',always_xy=True)
lon,lat=inv.transform(x,y); assert abs(lon-4.3517)<1e-5 and abs(lat-50.8503)<1e-5
cells=[{'cell_id':'hit','bbox':[x-10,y-10,x+10,y+10]},{'cell_id':'other','bbox':[0,0,1,1]}]
r=m.index_records([{'canonical_id':'a','lat':50.8503,'lon':4.3517},{'canonical_id':'b','lat':None,'lon':None}],cells)
assert r[0]['cell_ids']==['hit'] and r[0]['spatial_status']=='INDEXED'
assert r[1]['spatial_status']=='MISSING_COORDINATES'
assert m.locate(x+100,y+100,cells)==[]
print('REFERENCE_SPATIAL_INDEX_GUARDRAILS_OK crs=EPSG:31370 roundtrip=true cell_bounds=true')
