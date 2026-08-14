#!/usr/bin/env python3
import json, math, pathlib, urllib.parse, urllib.request

ANCHOR=(148093.22038698208,176091.76722726133)
CAMERA=(ANCHOR[0]+120.0,ANCHOR[1])
HALF_HFOV=math.degrees(math.atan(math.tan(math.radians(48.0/2.0))*(16.0/9.0)))
BBOX=(147980.0,175930.0,148330.0,176260.0)
ENDPOINT="https://geoservices-urbis.irisnet.be/geoserver/inspirevector/ows"
TARGET_ID="LandCover.1038"

params={"service":"WFS","version":"2.0.0","request":"GetFeature","typeNames":"LandCover",
        "outputFormat":"application/json","srsName":"EPSG:31370",
        "bbox":",".join(map(str,BBOX))+",EPSG:31370","count":"500"}
url=ENDPOINT+"?"+urllib.parse.urlencode(params)
req=urllib.request.Request(url,headers={"User-Agent":"Grand-Bruxelles-source-gate/1.3","Accept":"application/json"})
with urllib.request.urlopen(req,timeout=45) as response:
    payload=json.load(response)
feature=next((f for f in payload.get("features",[]) if f.get("id")==TARGET_ID),None)
if feature is None:
    raise SystemExit(f"{TARGET_ID} disappeared from official WFS query")
geom=feature.get("geometry") or {}
props=feature.get("properties") or {}
if geom.get("type") not in ("Polygon","MultiPolygon") or props.get("gml_descri")!="GB":
    raise SystemExit("Candidate lost polygon/GB source contract")

def polygons(g):
    c=g.get("coordinates",[])
    return [c] if g.get("type")=="Polygon" else c

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
        if poly:
            total += area_ring(poly[0])-sum(area_ring(h) for h in poly[1:])
    return max(0.0,total)

samples=[]; inside_count=0
# Uniform 5 m samples across the accepted horizontal ground wedge from 5 m to 120 m.
for forward in range(5,121,5):
    half_width=math.tan(math.radians(HALF_HFOV))*forward
    lateral=-half_width
    while lateral<=half_width+1e-9:
        p=(CAMERA[0]-forward,CAMERA[1]+lateral)
        inside=point_in_geom(p,geom)
        samples.append([round(p[0],3),round(p[1],3),inside])
        inside_count += int(inside)
        lateral += 5.0
coverage=inside_count/len(samples) if samples else 0.0
points=[q for p in polygons(geom) for ring in p for q in ring]
min_e=min(q[0] for q in points); max_e=max(q[0] for q in points)
min_n=min(q[1] for q in points); max_n=max(q[1] for q in points)
out={
    "schema":1,"format":"grand-bruxelles-atomium-landcover-source-gate-v1",
    "source":{"organization":"Paradigm","service":"INSPIRE vector Brussels WFS","endpoint":ENDPOINT,
              "layer":"LandCover","query_url":url,"crs":"EPSG:31370","feature_id":TARGET_ID,
              "begin_date":props.get("begin_date"),"gml_id":props.get("gml_id"),"inspire_id":props.get("insp_id")},
    "classification":{"source_code":props.get("gml_descri"),"coverage_percent":props.get("cov_perc"),
                      "interpretation":"Green Block / zone verte; broad vegetated amenity footprint only",
                      "interpretation_source":"UrbIS-Map technical specification; do not infer exact grass/tree species/material photometry"},
    "geometry":{"type":geom.get("type"),"area_m2":round(area_geom(geom),3),
                "bbox_epsg31370":[round(min_e,3),round(min_n,3),round(max_e,3),round(max_n,3)],
                "coordinates":geom.get("coordinates")},
    "accepted_player_witness":{"camera_epsg31370":list(CAMERA),"atomium_anchor_epsg31370":list(ANCHOR),
                               "vertical_fov_deg":48.0,"horizontal_half_fov_deg":HALF_HFOV,
                               "camera_inside_candidate":point_in_geom(CAMERA,geom),
                               "atomium_anchor_inside_candidate":point_in_geom(ANCHOR,geom),
                               "ground_wedge_sample_spacing_m":5.0,"ground_wedge_sample_count":len(samples),
                               "ground_wedge_inside_count":inside_count,"ground_wedge_coverage_fraction":coverage},
    "runtime_policy":{"runtime_approved":False,"material_photometry_resolved":False,"vegetation_geometry_resolved":False,
                      "may_only_proceed_if_ground_wedge_coverage_fraction_at_least":0.20},
}
path=pathlib.Path("artifacts/atomium/landcover_1038_candidate.json")
path.parent.mkdir(parents=True,exist_ok=True)
path.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding="utf-8")
print("ATOMIUM_LANDCOVER_CANDIDATE_OK",json.dumps({
    "camera_inside":out["accepted_player_witness"]["camera_inside_candidate"],
    "anchor_inside":out["accepted_player_witness"]["atomium_anchor_inside_candidate"],
    "wedge_coverage":round(coverage,4),"area_m2":out["geometry"]["area_m2"],"bbox":out["geometry"]["bbox_epsg31370"]}))
if coverage < 0.20:
    raise SystemExit(f"GB foreground covers only {coverage:.3%} of accepted wedge samples; reject before runtime")
