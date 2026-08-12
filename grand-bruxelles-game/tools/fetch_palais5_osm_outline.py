#!/usr/bin/env python3
"""Fetch OSM way 143816182 and validate its hall outline against aggregate UrbIS.

UrbIS feature 278 aggregates the Brussels Expo complex rather than exposing a
clean Palais 5 polygon. The Grand Bruxelles local frame uses +X east and -Z north,
so the WGS84->Lambert72 deltas map with x_sign=+1 and z_sign=-1. Validation is
therefore based on containment in the official complex bbox, centroid agreement,
and substantial overlap with the aggregate UrbIS polygon instead of demanding a
95% per-vertex match against a deliberately coarser/aggregated source.
"""
from __future__ import annotations
import json, math, urllib.request, xml.etree.ElementTree as ET
from pathlib import Path
from pyproj import Transformer

WAY_ID=143816182
URL=f'https://api.openstreetmap.org/api/0.6/way/{WAY_ID}/full'
OUT=Path('data/sources/laeken_jette/palais5_osm_outline.game.json')
BUILDINGS=Path('data/urbis/laeken_jette/buildings.game.json')
FEATURE_INDEX=278
LOCATOR_LAT=50.89969
LOCATOR_LON=4.33721
LOCATOR_LOCAL=(-87.23317646887153,-7056.078922991641)
EXPECTED_INSPIRE='https://databrussels.be/id/building/1635598'
X_SIGN=1.0
Z_SIGN=-1.0

def ring(raw):
    pts=[(float(p[0]),float(p[1])) for p in raw if isinstance(p,list) and len(p)>=2]
    if len(pts)>=2 and math.dist(pts[0],pts[-1])<1e-6: pts.pop()
    return pts

def point_in_ring(p,r):
    x,z=p; inside=False; j=len(r)-1
    for i,(xi,zi) in enumerate(r):
        xj,zj=r[j]
        if ((zi>z)!=(zj>z)) and x < (xj-xi)*(z-zi)/(zj-zi)+xi: inside=not inside
        j=i
    return inside

def polygons_for(geometry):
    kind=geometry.get('type'); coords=geometry.get('coordinates') or []
    return coords if kind=='MultiPolygon' else [coords] if kind=='Polygon' else []

def inside_feature(p,geometry):
    for poly in polygons_for(geometry):
        if not poly: continue
        outer=ring(poly[0])
        if point_in_ring(p,outer) and not any(point_in_ring(p,ring(h)) for h in poly[1:]): return True
    return False

def feature_bbox(geometry):
    pts=[]
    for poly in polygons_for(geometry):
        for rr in poly:
            pts.extend(ring(rr))
    assert pts
    return min(x for x,_ in pts),max(x for x,_ in pts),min(z for _,z in pts),max(z for _,z in pts)

def area_centroid(points):
    if len(points)<3: return 0.0,(0.0,0.0)
    a2=0.0; cx=cz=0.0
    for i,(x0,z0) in enumerate(points):
        x1,z1=points[(i+1)%len(points)]; c=x0*z1-x1*z0
        a2+=c; cx+=(x0+x1)*c; cz+=(z0+z1)*c
    if abs(a2)<1e-9: return 0.0,(sum(x for x,_ in points)/len(points),sum(z for _,z in points)/len(points))
    return abs(a2)*0.5,(cx/(3*a2),cz/(3*a2))

def pca(points):
    cx=sum(x for x,_ in points)/len(points); cz=sum(z for _,z in points)/len(points)
    c=[(x-cx,z-cz) for x,z in points]
    xx=sum(x*x for x,_ in c)/len(c); zz=sum(z*z for _,z in c)/len(c); xz=sum(x*z for x,z in c)/len(c)
    ang=.5*math.atan2(2*xz,xx-zz); ax=(math.cos(ang),math.sin(ang)); sd=(-ax[1],ax[0])
    ma=[x*ax[0]+z*ax[1] for x,z in c]; mi=[x*sd[0]+z*sd[1] for x,z in c]
    return math.degrees(ang),max(ma)-min(ma),max(mi)-min(mi)

def main():
    req=urllib.request.Request(URL,headers={'User-Agent':'GrandBruxellesGame/1.0 (source audit)'})
    xml=urllib.request.urlopen(req,timeout=30).read(); root=ET.fromstring(xml)
    nodes={n.attrib['id']:(float(n.attrib['lat']),float(n.attrib['lon'])) for n in root.findall('node')}
    way=next((w for w in root.findall('way') if int(w.attrib['id'])==WAY_ID),None); assert way is not None
    ids=[nd.attrib['ref'] for nd in way.findall('nd')]; latlon=[nodes[i] for i in ids]
    if len(latlon)>=2 and latlon[0]==latlon[-1]: latlon.pop()
    assert len(latlon)>=4

    transformer=Transformer.from_crs('EPSG:4326','EPSG:31370',always_xy=True)
    lx0,ly0=transformer.transform(LOCATOR_LON,LOCATOR_LAT)
    projected=[transformer.transform(lon,lat) for lat,lon in latlon]
    local=[(LOCATOR_LOCAL[0]+X_SIGN*(x-lx0),LOCATOR_LOCAL[1]+Z_SIGN*(y-ly0)) for x,y in projected]

    buildings=json.loads(BUILDINGS.read_text(encoding='utf-8')); feature=buildings['features'][FEATURE_INDEX]
    assert (feature.get('properties') or {}).get('INSPIRE_ID')==EXPECTED_INSPIRE
    geometry=feature['geometry']; minx,maxx,minz,maxz=feature_bbox(geometry)
    inside_count=sum(1 for p in local if inside_feature(p,geometry))
    bbox_count=sum(1 for x,z in local if minx<=x<=maxx and minz<=z<=maxz)
    inside_share=inside_count/len(local); bbox_share=bbox_count/len(local)
    area,cent=area_centroid(local); centroid_distance=math.dist(cent,LOCATOR_LOCAL)
    angle,major,minor=pca(local)

    assert bbox_share==1.0, (bbox_share,(minx,maxx,minz,maxz))
    assert inside_share>=0.70, inside_share
    assert centroid_distance<=5.0, centroid_distance
    assert 500.0<=area<=60000.0, area
    assert major>=20.0 and minor>=20.0, (major,minor)

    tags={t.attrib['k']:t.attrib['v'] for t in way.findall('tag')}
    out={
      'schema':2,'source':'OpenStreetMap API','osm_way_id':WAY_ID,'osm_tags':tags,
      'semantic_role':'Palais 5 hall outline detail inside monolithic official UrbIS Expo feature',
      'validation':{'urbis_feature_index':FEATURE_INDEX,'urbis_inspire_id':EXPECTED_INSPIRE,'axis_mapping':{'x_sign':X_SIGN,'z_sign':Z_SIGN,'project_frame':'+X east, -Z north'},'vertex_inside_share':inside_share,'vertex_inside_complex_bbox_share':bbox_share,'centroid_distance_to_locator_m':centroid_distance,'aggregate_geometry_note':'UrbIS feature 278 is one large Expo polygon with holes; OSM supplies the individual hall outline while UrbIS remains the authoritative complex anchor.'},
      'geometry':{'type':'Polygon','coordinates':[[[round(x,6),round(z,6)] for x,z in local]+[[round(local[0][0],6),round(local[0][1],6)]]]},
      'metrics':{'vertex_count':len(local),'area_m2':round(area,3),'centroid_x':round(cent[0],3),'centroid_z':round(cent[1],3),'pca_angle_deg':round(angle,3),'major_span_m':round(major,3),'minor_span_m':round(minor,3),'min_x':round(min(x for x,_ in local),3),'max_x':round(max(x for x,_ in local),3),'min_z':round(min(z for _,z in local),3),'max_z':round(max(z for _,z in local),3)},
      'policy':'OSM is used only to separate/name the hall inside the official UrbIS Expo complex; terrain, global complex placement and official building height remain UrbIS/DTM/DSM governed.'
    }
    OUT.parent.mkdir(parents=True,exist_ok=True); OUT.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('PALAIS5_OSM_OUTLINE_OK',json.dumps({'vertices':len(local),'area':area,'centroid':cent,'angle':angle,'major':major,'minor':minor,'inside_share':inside_share,'bbox_share':bbox_share,'axis':(X_SIGN,Z_SIGN)},ensure_ascii=False))
if __name__=='__main__': main()
