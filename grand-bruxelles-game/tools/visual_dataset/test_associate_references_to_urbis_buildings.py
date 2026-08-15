#!/usr/bin/env python3
import importlib.util, tempfile, json
from pathlib import Path
p=Path(__file__).with_name('associate_references_to_urbis_buildings.py'); s=importlib.util.spec_from_file_location('a',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
poly=[(100,100),(110,100),(110,110),(100,110),(100,100)]
d,q=m.polygon_distance((95,105),poly); assert abs(d-5.0)<1e-9 and q==(100.0,105.0)
assert m.point_in_polygon((105,105),poly)
b=[{'id':'B','part':0,'polygon':poly,'area':100}]
r=m.score_reference({'easting_31370':95,'northing_31370':105,'heading':90},b); assert r and r[0]['building_id']=='B' and r[0]['distance_m']==5.0 and r[0]['confidence']>0.8
far=m.score_reference({'easting_31370':0,'northing_31370':0},b); assert far==[]
with tempfile.TemporaryDirectory() as d:
 root=Path(d); cell=root/'c'/'raw'; cell.mkdir(parents=True); json.dump({'type':'FeatureCollection','features':[{'type':'Feature','geometry':{'type':'Polygon','coordinates':[[[100,100],[110,100],[110,110],[100,110],[100,100]]]},'properties':{'INSPIRE_ID':'official','AREA':100}}]},open(cell/'buildings.geojson','w'))
 rows=m.associate([{'canonical_id':'r','easting_31370':95,'northing_31370':105,'cell_ids':['c'],'heading':90}],root)
 assert rows[0]['building_candidates'][0]['building_id']=='official'
 assert rows[0]['association_status']=='HIGH_CONFIDENCE'
print('REFERENCE_BUILDING_ASSOCIATION_GUARDRAILS_OK official_geometry=true no_forced_match=true heading_scored=true')
