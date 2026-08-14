#!/usr/bin/env python3
import json, math, pathlib, urllib.parse, urllib.request, urllib.error

ANCHOR=(148093.22038698208,176091.76722726133)
CAMERA=(ANCHOR[0]+120.0,ANCHOR[1])
HALF_HFOV=math.degrees(math.atan(math.tan(math.radians(48.0/2.0))*(16.0/9.0)))
BBOX=(147980.0,175930.0,148330.0,176260.0)
ROUTES=[
 ('https://data.mobility.brussels/geoserver/bm_urbis/wfs','bm_urbis:urbadm_ssw'),
 ('https://data-mobility.irisnet.be/geoserver/bm_urbis/wfs','bm_urbis:urbadm_ssw'),
]
VARIANTS=[('1.1.0','typeName','json','maxFeatures'),('1.1.0','typeName','application/json','maxFeatures'),('2.0.0','typeNames','application/json','count')]

payload=None; accepted_url=None; attempts=[]
for endpoint,type_name in ROUTES:
    for version,type_key,output,count_key in VARIANTS:
        params={'service':'WFS','version':version,'request':'GetFeature',type_key:type_name,'outputFormat':output,
                'srsName':'EPSG:31370','bbox':','.join(map(str,BBOX))+',EPSG:31370',count_key:'2000'}
        url=endpoint+'?'+urllib.parse.urlencode(params)
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'Grand-Bruxelles-source-gate/1.0','Accept':'application/json,application/geo+json,*/*'})
            with urllib.request.urlopen(req,timeout=45) as response:
                raw=response.read(); ctype=response.headers.get('Content-Type','')
            attempts.append({'url':url,'content_type':ctype,'bytes':len(raw),'preview':raw[:200].decode('utf-8','replace').replace('\n',' ')})
            if raw.lstrip().startswith((b'{',b'[')):
                candidate=json.loads(raw)
                if isinstance(candidate,dict) and isinstance(candidate.get('features'),list):
                    payload=candidate; accepted_url=url; break
        except Exception as exc:
            attempts.append({'url':url,'error':repr(exc)})
    if payload is not None: break
if payload is None:
    raise SystemExit('Official sidewalk WFS did not return GeoJSON: '+json.dumps(attempts,ensure_ascii=False))

def polygons(g):
    if not isinstance(g,dict): return []
    c=g.get('coordinates',[]); t=g.get('type')
    return [c] if t=='Polygon' else c if t=='MultiPolygon' else []

def point_in_ring(point,ring):
    x,y=point; inside=False; j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i][0],ring[i][1]; xj,yj=ring[j][0],ring[j][1]
        if ((yi>y)!=(yj>y)) and (x < (xj-xi)*(y-yi)/((yj-yi) if abs(yj-yi)>1e-12 else 1e-12)+xi): inside=not inside
        j=i
    return inside

def point_in_geom(point,g):
    for poly in polygons(g):
        if poly and point_in_ring(point,poly[0]) and not any(point_in_ring(point,h) for h in poly[1:]): return True
    return False

def area_ring(r):
    return 0.0 if len(r)<4 else abs(sum(r[i][0]*r[i+1][1]-r[i+1][0]*r[i][1] for i in range(len(r)-1)))*0.5

def area_geom(g):
    return sum(area_ring(p[0])-sum(area_ring(h) for h in p[1:]) for p in polygons(g) if p)

features=[]
for f in payload.get('features',[]):
    g=f.get('geometry') or {}
    if polygons(g): features.append({'id':f.get('id'),'properties':f.get('properties') or {},'geometry':g,'area_m2':max(0.0,area_geom(g))})

green=json.load(open('data/environment/laeken_jette/atomium_landcover_context.game.json',encoding='utf-8'))['geometry']
samples=[]; sidewalk_hits=0; exclusive_hits=0; overlap_hits=0
for forward in range(5,121,5):
    half_width=math.tan(math.radians(HALF_HFOV))*forward
    lateral=-half_width
    while lateral<=half_width+1e-9:
        p=(CAMERA[0]-forward,CAMERA[1]+lateral)
        ids=[f['id'] for f in features if point_in_geom(p,f['geometry'])]
        in_sidewalk=bool(ids); in_green=point_in_geom(p,green)
        sidewalk_hits += int(in_sidewalk); overlap_hits += int(in_sidewalk and in_green); exclusive_hits += int(in_sidewalk and not in_green)
        samples.append([round(p[0],3),round(p[1],3),ids,in_green]); lateral+=5.0
count=len(samples); exclusive=exclusive_hits/count if count else 0.0; total=sidewalk_hits/count if count else 0.0
rank=sorted(({'id':f['id'],'area_m2':round(f['area_m2'],3),'properties':f['properties']} for f in features),key=lambda x:-x['area_m2'])
out={'schema':1,'format':'grand-bruxelles-atomium-sidewalk-projection-v1','source':{'organization':'Paradigm','publisher':'Brussels Mobility','dataset':'Trottoir / Sidewalk','layer':'bm_urbis:urbadm_ssw','query_url':accepted_url,'crs':'EPSG:31370','license':'CC0','metadata_url':'https://data.mobility.brussels/en/info/urbadm_ssw/'},'witness':{'camera_epsg31370':list(CAMERA),'atomium_anchor_epsg31370':list(ANCHOR),'vertical_fov_deg':48.0,'horizontal_half_fov_deg':HALF_HFOV,'sample_spacing_m':5.0,'sample_count':count,'sidewalk_hit_count':sidewalk_hits,'sidewalk_coverage_fraction':total,'green_overlap_hit_count':overlap_hits,'exclusive_sidewalk_hit_count':exclusive_hits,'exclusive_sidewalk_coverage_fraction':exclusive},'feature_count':len(features),'top_features':rank[:12],'attempts':attempts}
path=pathlib.Path('artifacts/atomium/sidewalk_projection_probe.json'); path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print('ATOMIUM_SIDEWALK_PROJECTION_OK',json.dumps(out['witness'],ensure_ascii=False))
if exclusive < 0.06:
    raise SystemExit(f'REJECT: sidewalk exclusive coverage {exclusive:.3%} < 6% in actual player wedge')
