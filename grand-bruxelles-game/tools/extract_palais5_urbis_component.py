#!/usr/bin/env python3
"""Isolate the precise UrbIS polygon component containing the Palais 5 locator.

Identity/location comes from the previously audited OSM way 143816182 centre.
Building geometry remains the committed UrbIS feature 278. This script never
changes city geometry; it emits a compact audited component for hero-detail work.
"""
from __future__ import annotations
import json, math
from pathlib import Path

BUILDINGS=Path('data/urbis/laeken_jette/buildings.game.json')
HEIGHTS=Path('data/urbis/laeken_jette/building_heights_dsm.game.json')
OUTPUT=Path('data/sources/laeken_jette/palais5_urbis_component.json')
FEATURE_INDEX=278
LOCATOR=(-87.23317646887153,-7056.078922991641)
EXPECTED_INSPIRE='https://databrussels.be/id/building/1635598'

def ring_points(raw):
    pts=[(float(p[0]),float(p[1])) for p in raw if isinstance(p,list) and len(p)>=2]
    if len(pts)>=2 and math.hypot(pts[0][0]-pts[-1][0],pts[0][1]-pts[-1][1])<1e-6: pts.pop()
    return pts

def point_in_ring(point,ring):
    x,z=point; inside=False; j=len(ring)-1
    for i,(xi,zi) in enumerate(ring):
        xj,zj=ring[j]
        if ((zi>z)!=(zj>z)) and x < (xj-xi)*(z-zi)/(zj-zi)+xi: inside=not inside
        j=i
    return inside

def polygon_contains(point,poly):
    if not poly or not point_in_ring(point,ring_points(poly[0])): return False
    return not any(point_in_ring(point,ring_points(h)) for h in poly[1:])

def polygon_area(ring):
    return abs(sum(ring[i][0]*ring[(i+1)%len(ring)][1]-ring[(i+1)%len(ring)][0]*ring[i][1] for i in range(len(ring)))*0.5)

def centroid(ring):
    signed=sum(ring[i][0]*ring[(i+1)%len(ring)][1]-ring[(i+1)%len(ring)][0]*ring[i][1] for i in range(len(ring)))
    if abs(signed)<1e-9: return (sum(x for x,_ in ring)/len(ring),sum(z for _,z in ring)/len(ring))
    cx=cz=0.0
    for i in range(len(ring)):
        x0,z0=ring[i]; x1,z1=ring[(i+1)%len(ring)]; cross=x0*z1-x1*z0
        cx+=(x0+x1)*cross; cz+=(z0+z1)*cross
    return cx/(3*signed),cz/(3*signed)

def pca(ring):
    cx=sum(x for x,_ in ring)/len(ring); cz=sum(z for _,z in ring)/len(ring)
    c=[(x-cx,z-cz) for x,z in ring]
    xx=sum(x*x for x,_ in c)/len(c); zz=sum(z*z for _,z in c)/len(c); xz=sum(x*z for x,z in c)/len(c)
    angle=.5*math.atan2(2*xz,xx-zz); axis=(math.cos(angle),math.sin(angle)); side=(-axis[1],axis[0])
    major=[x*axis[0]+z*axis[1] for x,z in c]; minor=[x*side[0]+z*side[1] for x,z in c]
    return math.degrees(angle),max(major)-min(major),max(minor)-min(minor)

def main():
    buildings=json.loads(BUILDINGS.read_text()); heights=json.loads(HEIGHTS.read_text())
    f=buildings['features'][FEATURE_INDEX]; props=f.get('properties') or {}; assert props.get('INSPIRE_ID')==EXPECTED_INSPIRE
    g=f.get('geometry') or {}; kind=g.get('type'); coords=g.get('coordinates') or []
    polygons=coords if kind=='MultiPolygon' else [coords] if kind=='Polygon' else []; assert polygons
    components=[]; containing=[]
    for idx,poly in enumerate(polygons):
        if not poly: continue
        outer=ring_points(poly[0]);
        if len(outer)<3: continue
        cx,cz=centroid(outer); angle,major,minor=pca(outer)
        item={'component_index':idx,'contains_palais5_locator':polygon_contains(LOCATOR,poly),'outer_vertex_count':len(outer),'hole_count':max(0,len(poly)-1),'outer_area_m2':round(polygon_area(outer),3),'centroid_x':round(cx,3),'centroid_z':round(cz,3),'centroid_distance_to_locator_m':round(math.hypot(cx-LOCATOR[0],cz-LOCATOR[1]),3),'min_x':round(min(x for x,_ in outer),3),'max_x':round(max(x for x,_ in outer),3),'min_z':round(min(z for _,z in outer),3),'max_z':round(max(z for _,z in outer),3),'pca_angle_deg':round(angle,3),'major_span_m':round(major,3),'minor_span_m':round(minor,3)}
        components.append(item)
        if item['contains_palais5_locator']: containing.append((item,poly,outer))
    assert len(containing)==1, f'expected one containing component, got {len(containing)}'
    selected,poly,outer=containing[0]
    out={'schema':1,'identity':{'name':'Palais 5 / Paleis 5','semantic_source':'OpenStreetMap','osm_way_id':143816182,'locator_local_x':LOCATOR[0],'locator_local_z':LOCATOR[1]},'geometry_source':'Paradigm UrbIS Buildings WFS committed local dataset','source_feature_index':FEATURE_INDEX,'source_inspire_id':EXPECTED_INSPIRE,'source_geometry_type':kind,'source_component_count':len(polygons),'selected_component':selected,'height_record':heights['records'][FEATURE_INDEX],'outer_ring':[[round(x,6),round(z,6)] for x,z in outer],'holes':[[[round(x,6),round(z,6)] for x,z in ring_points(h)] for h in poly[1:]],'nearest_components_by_centroid':sorted(components,key=lambda c:c['centroid_distance_to_locator_m'])[:12],'policy':'Only this point-containing UrbIS polygon component may receive Palais 5 hero detailing. The larger feature remains untouched and no facade dimensions are inferred by this audit.'}
    OUTPUT.parent.mkdir(parents=True,exist_ok=True); OUTPUT.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n')
    print('PALAIS5_URBIS_COMPONENT_OK',json.dumps(selected,ensure_ascii=False))
if __name__=='__main__': main()
