#!/usr/bin/env python3
import hashlib, json, math, pathlib, urllib.parse, urllib.request

ANCHOR=(148093.22038698208,176091.76722726133)
CAMERA=(ANCHOR[0]+120.0,ANCHOR[1])
HALF_HFOV=math.degrees(math.atan(math.tan(math.radians(48.0/2.0))*(16.0/9.0)))
BBOX=(147980.0,175930.0,148330.0,176260.0)
ROUTES=[('https://data.mobility.brussels/geoserver/bm_urbis/wfs','bm_urbis:urbadm_ssw'),('https://data-mobility.irisnet.be/geoserver/bm_urbis/wfs','bm_urbis:urbadm_ssw')]
VARIANTS=[('1.1.0','typeName','json','maxFeatures'),('1.1.0','typeName','application/json','maxFeatures'),('2.0.0','typeNames','application/json','count')]
payload=None; accepted_url=None; attempts=[]
for endpoint,type_name in ROUTES:
    for version,type_key,output,count_key in VARIANTS:
        params={'service':'WFS','version':version,'request':'GetFeature',type_key:type_name,'outputFormat':output,'srsName':'EPSG:31370','bbox':','.join(map(str,BBOX))+',EPSG:31370',count_key:'2000'}
        url=endpoint+'?'+urllib.parse.urlencode(params)
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'Grand-Bruxelles-source-gate/1.0','Accept':'application/json,application/geo+json,*/*'})
            with urllib.request.urlopen(req,timeout=45) as response: raw=response.read(); ctype=response.headers.get('Content-Type','')
            attempts.append({'url':url,'content_type':ctype,'bytes':len(raw)})
            if raw.lstrip().startswith((b'{',b'[')):
                candidate=json.loads(raw)
                if isinstance(candidate,dict) and isinstance(candidate.get('features'),list): payload=candidate; accepted_url=url; break
        except Exception as exc: attempts.append({'url':url,'error':repr(exc)})
    if payload is not None: break
if payload is None: raise SystemExit('Official sidewalk WFS did not return GeoJSON: '+json.dumps(attempts,ensure_ascii=False))

def polygons(g):
    if not isinstance(g,dict): return []
    c=g.get('coordinates',[]); t=g.get('type')
    return [c] if t=='Polygon' else c if t=='MultiPolygon' else []
def point_in_ring(point,ring):
    x,y=point; inside=False; j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i][0],ring[i][1]; xj,yj=ring[j][0],ring[j][1]
        if ((yi>y)!=(yj>y)) and x < (xj-xi)*(y-yi)/((yj-yi) if abs(yj-yi)>1e-12 else 1e-12)+xi: inside=not inside
        j=i
    return inside
def point_in_geom(point,g):
    return any(poly and point_in_ring(point,poly[0]) and not any(point_in_ring(point,h) for h in poly[1:]) for poly in polygons(g))
def canon_geom(g):
    def ring(r): return [[round(float(p[0]),3),round(float(p[1]),3)] for p in r]
    return {'type':g.get('type'),'coordinates':[[ring(r) for r in poly] for poly in polygons(g)]} if g.get('type')=='MultiPolygon' else {'type':'Polygon','coordinates':[ring(r) for r in (polygons(g)[0] if polygons(g) else [])]}
def geom_bbox(g):
    pts=[p for poly in polygons(g) for ring in poly for p in ring]
    if not pts: return None
    xs=[float(p[0]) for p in pts]; ys=[float(p[1]) for p in pts]
    return (min(xs),min(ys),max(xs),max(ys))
def bbox_contains(b,p): return b is not None and b[0] <= p[0] <= b[2] and b[1] <= p[1] <= b[3]
features=[]
for f in payload.get('features',[]):
    g=f.get('geometry') or {}
    if polygons(g):
        cg=canon_geom(g); features.append({'id':str(f.get('id','')),'geometry':cg,'bbox':geom_bbox(cg)})
features.sort(key=lambda f:f['id'])
green=json.load(open('data/environment/laeken_jette/atomium_landcover_context.game.json',encoding='utf-8'))['geometry']
samples=[]; sidewalk_hits=exclusive_hits=overlap_hits=0; used_ids=set()
for forward in range(5,121,5):
    half_width=math.tan(math.radians(HALF_HFOV))*forward; lateral=-half_width
    while lateral<=half_width+1e-9:
        p=(CAMERA[0]-forward,CAMERA[1]+lateral)
        ids=[f['id'] for f in features if bbox_contains(f['bbox'],p) and point_in_geom(p,f['geometry'])]
        used_ids.update(ids); ins=bool(ids); ing=point_in_geom(p,green); sidewalk_hits+=int(ins); overlap_hits+=int(ins and ing); exclusive_hits+=int(ins and not ing)
        samples.append([round(p[0],3),round(p[1],3),ids,ing]); lateral+=5.0
count=len(samples); exclusive=exclusive_hits/count if count else 0.0
# Lock only exact source features that actually intersect the accepted player wedge.
locked=[{'id':f['id'],'geometry':f['geometry']} for f in features if f['id'] in used_ids]
canonical=json.dumps(locked,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode(); geometry_sha=hashlib.sha256(canonical).hexdigest()
out={'schema':2,'format':'grand-bruxelles-atomium-sidewalk-source-v2','source':{'organization':'Paradigm','publisher':'Brussels Mobility','dataset':'Trottoir / Sidewalk','layer':'bm_urbis:urbadm_ssw','query_url':accepted_url,'crs':'EPSG:31370','license':'CC0','metadata_url':'https://data.mobility.brussels/en/info/urbadm_ssw/','canonical_geometry_sha256':geometry_sha},'witness':{'camera_epsg31370':list(CAMERA),'atomium_anchor_epsg31370':list(ANCHOR),'vertical_fov_deg':48.0,'horizontal_half_fov_deg':HALF_HFOV,'sample_spacing_m':5.0,'sample_count':count,'sidewalk_hit_count':sidewalk_hits,'green_overlap_hit_count':overlap_hits,'exclusive_sidewalk_hit_count':exclusive_hits,'exclusive_sidewalk_coverage_fraction':exclusive},'feature_count':len(locked),'features':locked}
path=pathlib.Path('artifacts/atomium/atomium_sidewalk_source_lock.game.json'); path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print('ATOMIUM_SIDEWALK_SOURCE_OK',json.dumps(out['witness'],ensure_ascii=False),'sha256='+geometry_sha,'features='+str(len(locked)))
if exclusive < 0.06: raise SystemExit(f'REJECT: sidewalk exclusive coverage {exclusive:.3%} < 6% in actual player wedge')
