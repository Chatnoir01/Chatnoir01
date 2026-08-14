#!/usr/bin/env python3
import json, math, pathlib, urllib.parse, urllib.request

ANCHOR=(148093.22038698208,176091.76722726133)
CAMERA=(ANCHOR[0]+120.0,ANCHOR[1])
HALF_HFOV=math.degrees(math.atan(math.tan(math.radians(48.0/2.0))*(16.0/9.0)))
BBOX=(147980.0,175930.0,148330.0,176260.0)
ENDPOINT='https://geoservices-urbis.irisnet.be/geoserver/ows'
TYPE='inspire:TN.RoadTransportNetwork.RoadArea'

params={'service':'WFS','version':'2.0.0','request':'GetFeature','typeNames':TYPE,
        'outputFormat':'application/json','srsName':'EPSG:31370',
        'bbox':','.join(map(str,BBOX))+',EPSG:31370','count':'1000'}
url=ENDPOINT+'?'+urllib.parse.urlencode(params)
req=urllib.request.Request(url,headers={'User-Agent':'Grand-Bruxelles-source-gate/1.0','Accept':'application/json'})
with urllib.request.urlopen(req,timeout=45) as response:
    payload=json.load(response)

def polygons(g):
    if not isinstance(g,dict): return []
    c=g.get('coordinates',[]); t=g.get('type')
    return [c] if t=='Polygon' else c if t=='MultiPolygon' else []

def point_in_ring(point,ring):
    x,y=point; inside=False
    if len(ring)<3:return False
    j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i][0],ring[i][1]; xj,yj=ring[j][0],ring[j][1]
        hit=((yi>y)!=(yj>y)) and (x < (xj-xi)*(y-yi)/((yj-yi) if abs(yj-yi)>1e-12 else 1e-12)+xi)
        if hit: inside=not inside
        j=i
    return inside

def point_in_geom(point,g):
    for poly in polygons(g):
        if not poly or not point_in_ring(point,poly[0]): continue
        if any(point_in_ring(point,hole) for hole in poly[1:]): continue
        return True
    return False

def area_ring(r):
    if len(r)<4:return 0.0
    return abs(sum(r[i][0]*r[i+1][1]-r[i+1][0]*r[i][1] for i in range(len(r)-1)))*0.5

def area_geom(g):
    total=0.0
    for poly in polygons(g):
        if poly: total += area_ring(poly[0])-sum(area_ring(h) for h in poly[1:])
    return max(0.0,total)

features=[]
for f in payload.get('features',[]):
    g=f.get('geometry') or {}
    if not polygons(g): continue
    features.append({'id':f.get('id'),'properties':f.get('properties') or {},'geometry':g,'area_m2':area_geom(g)})

samples=[]; road_hits=0
for forward in range(5,121,5):
    half_width=math.tan(math.radians(HALF_HFOV))*forward
    lateral=-half_width
    while lateral<=half_width+1e-9:
        p=(CAMERA[0]-forward,CAMERA[1]+lateral)
        ids=[f['id'] for f in features if point_in_geom(p,f['geometry'])]
        road_hits += int(bool(ids))
        samples.append([round(p[0],3),round(p[1],3),ids])
        lateral += 5.0
coverage=road_hits/len(samples) if samples else 0.0
rank=[]
for f in features:
    pts=[q for p in polygons(f['geometry']) for ring in p for q in ring]
    min_e=min(q[0] for q in pts); max_e=max(q[0] for q in pts); min_n=min(q[1] for q in pts); max_n=max(q[1] for q in pts)
    rank.append({'id':f['id'],'area_m2':round(f['area_m2'],3),'bbox_epsg31370':[round(min_e,3),round(min_n,3),round(max_e,3),round(max_n,3)],'properties':f['properties']})
rank.sort(key=lambda r:-r['area_m2'])
out={'schema':1,'format':'grand-bruxelles-atomium-roadarea-source-gate-v1',
     'source':{'organization':'Paradigm','service':'INSPIRE vector Brussels WFS','endpoint':ENDPOINT,'layer':TYPE,'crs':'EPSG:31370','query_url':url},
     'witness':{'camera_epsg31370':list(CAMERA),'atomium_anchor_epsg31370':list(ANCHOR),'vertical_fov_deg':48.0,'horizontal_half_fov_deg':HALF_HFOV,
                'sample_spacing_m':5.0,'sample_count':len(samples),'road_hit_count':road_hits,'ground_wedge_coverage_fraction':coverage},
     'feature_count':len(features),'features':rank,'samples':samples,
     'runtime_policy':{'runtime_approved':False,'material_photometry_resolved':False,'may_proceed_if_ground_wedge_coverage_fraction_at_least':0.08}}
path=pathlib.Path('artifacts/atomium/roadarea_context_probe.json'); path.parent.mkdir(parents=True,exist_ok=True)
path.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print('ATOMIUM_ROADAREA_PROBE_OK',json.dumps({'features':len(features),'coverage':round(coverage,4),'top':rank[:8]},ensure_ascii=False))
if coverage < 0.08:
    raise SystemExit(f'Official RoadArea covers only {coverage:.3%} of accepted ground wedge; reject before runtime')
