#!/usr/bin/env python3
"""Associate EPSG:31370 visual references with nearby authoritative UrbIS buildings.

Associations are candidates, never forced. Distance is authoritative; heading only
raises/lowers confidence when the reference source supplies it.
"""
from __future__ import annotations
import argparse, json, math
from pathlib import Path

MAX_DISTANCE_M=60.0
MAX_CANDIDATES=5

def point_in_polygon(p,poly):
    x,y=p; inside=False
    for i in range(len(poly)):
        x1,y1=poly[i]; x2,y2=poly[(i+1)%len(poly)]
        if ((y1>y)!=(y2>y)) and x < (x2-x1)*(y-y1)/(y2-y1)+x1: inside=not inside
    return inside

def closest_on_segment(p,a,b):
    px,py=p; ax,ay=a; bx,by=b; dx=bx-ax; dy=by-ay; den=dx*dx+dy*dy
    t=0.0 if den==0 else max(0.0,min(1.0,((px-ax)*dx+(py-ay)*dy)/den))
    q=(ax+t*dx,ay+t*dy); return q,math.hypot(px-q[0],py-q[1])

def polygon_distance(p,poly):
    if point_in_polygon(p,poly): return 0.0,p
    best=(float('inf'),p)
    for i in range(len(poly)-1 if poly and poly[0]==poly[-1] else len(poly)):
        q,d=closest_on_segment(p,poly[i],poly[(i+1)%len(poly)])
        if d<best[0]: best=(d,q)
    return best

def bearing_deg(a,b):
    dx=b[0]-a[0]; dy=b[1]-a[1]
    return (math.degrees(math.atan2(dx,dy))+360.0)%360.0

def angle_delta(a,b): return abs((a-b+180.0)%360.0-180.0)

def load_buildings(cell_root:Path,cell_id:str):
    path=cell_root/cell_id/'raw'/'buildings.geojson'
    if not path.exists(): return []
    fc=json.loads(path.read_text(encoding='utf-8')); out=[]
    for f in fc.get('features',[]):
        geom=f.get('geometry') or {}; coords=geom.get('coordinates') or []
        rings=[]
        if geom.get('type')=='Polygon': rings=coords[:1]
        elif geom.get('type')=='MultiPolygon': rings=[p[0] for p in coords if p]
        for n,ring in enumerate(rings):
            if len(ring)>=3:
                props=f.get('properties') or {}; out.append({'id':props.get('INSPIRE_ID') or f.get('id'),'part':n,'polygon':[(float(x),float(y)) for x,y,*_ in ring],'area':props.get('AREA')})
    return out

def score_reference(ref,buildings):
    if ref.get('easting_31370') is None or ref.get('northing_31370') is None: return []
    p=(float(ref['easting_31370']),float(ref['northing_31370'])); heading=ref.get('heading'); candidates=[]
    for b in buildings:
        d,q=polygon_distance(p,b['polygon'])
        if d>MAX_DISTANCE_M: continue
        view=bearing_deg(p,q) if d>0.01 else None
        heading_delta=None
        if heading is not None and view is not None:
            try: heading_delta=angle_delta(float(heading),view)
            except (TypeError,ValueError): heading_delta=None
        distance_score=max(0.0,1.0-d/MAX_DISTANCE_M)
        heading_score=0.5 if heading_delta is None else max(0.0,1.0-heading_delta/90.0)
        confidence=0.78*distance_score+0.22*heading_score
        candidates.append({'building_id':b['id'],'part':b['part'],'distance_m':round(d,3),'view_bearing_deg':None if view is None else round(view,2),'heading_delta_deg':None if heading_delta is None else round(heading_delta,2),'confidence':round(confidence,4),'area':b.get('area')})
    return sorted(candidates,key=lambda x:(-x['confidence'],x['distance_m'],str(x['building_id'])))[:MAX_CANDIDATES]

def associate(records,cell_root:Path):
    cache={}; out=[]
    for ref in records:
        buildings=[]
        for cell_id in sorted(ref.get('cell_ids') or []):
            if cell_id not in cache: cache[cell_id]=load_buildings(cell_root,cell_id)
            buildings.extend(cache[cell_id])
        item=dict(ref); item['building_candidates']=score_reference(ref,buildings)
        top=item['building_candidates'][0]['confidence'] if item['building_candidates'] else 0.0
        item['association_status']='HIGH_CONFIDENCE' if top>=0.75 else ('CANDIDATES' if item['building_candidates'] else 'UNMATCHED')
        out.append(item)
    return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--cell-root',default='grand-bruxelles-game/data/urbis/remaining_brussels/cells'); ap.add_argument('--output',required=True); a=ap.parse_args()
    p=json.loads(Path(a.input).read_text(encoding='utf-8')); rows=associate(p.get('records') or [],Path(a.cell_root)); summary={'records':len(rows),'high_confidence':sum(r['association_status']=='HIGH_CONFIDENCE' for r in rows),'with_candidates':sum(bool(r['building_candidates']) for r in rows),'unmatched':sum(r['association_status']=='UNMATCHED' for r in rows)}
    out={'format':'grand-bruxelles-reference-building-association-v1','geometry_authority':'UrbIS EPSG:31370 raw building footprints','summary':summary,'records':rows}; Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('REFERENCE_BUILDING_ASSOCIATION_OK',summary)
if __name__=='__main__': main()
