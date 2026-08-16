#!/usr/bin/env python3
from __future__ import annotations
import json, math, urllib.parse, urllib.request
from pathlib import Path
from typing import Any
from lambert72_to_game_geojson import DEFAULT_ORIGIN_E, DEFAULT_ORIGIN_N, convert_document

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:StreetSurfaces"
ANCHOR_GAME = (-272.04, -217.07)
ANCHOR_L72 = (DEFAULT_ORIGIN_E + ANCHOR_GAME[0], DEFAULT_ORIGIN_N - ANCHOR_GAME[1])
BBOX = (ANCHOR_L72[0]-90.0, ANCHOR_L72[1]-90.0, ANCHOR_L72[0]+90.0, ANCHOR_L72[1]+90.0)
OUT = Path("data/urbis/anneessens/place_identity.game.json")

def point_in_ring(x: float, y: float, ring: list[list[float]]) -> bool:
    inside = False
    j = len(ring)-1
    for i in range(len(ring)):
        xi, yi = float(ring[i][0]), float(ring[i][1]); xj, yj = float(ring[j][0]), float(ring[j][1])
        if ((yi > y) != (yj > y)) and x < (xj-xi)*(y-yi)/((yj-yi) or 1e-12)+xi: inside = not inside
        j = i
    return inside

def contains(geom: dict[str, Any], p: tuple[float,float]) -> bool:
    typ, c = geom.get("type"), geom.get("coordinates", [])
    polys = [c] if typ == "Polygon" else c if typ == "MultiPolygon" else []
    for poly in polys:
        if poly and point_in_ring(p[0], p[1], poly[0]):
            if not any(point_in_ring(p[0], p[1], hole) for hole in poly[1:]): return True
    return False

def centroid_ring(ring: list[list[float]]) -> tuple[float,float]:
    pts = ring[:-1] if len(ring)>1 and ring[0][:2] == ring[-1][:2] else ring
    a=cx=cy=0.0
    for i,p in enumerate(pts):
        q=pts[(i+1)%len(pts)]; cross=p[0]*q[1]-q[0]*p[1]; a+=cross; cx+=(p[0]+q[0])*cross; cy+=(p[1]+q[1])*cross
    if abs(a)<1e-9: return (sum(p[0] for p in pts)/len(pts),sum(p[1] for p in pts)/len(pts))
    return (cx/(3*a), cy/(3*a))

def outer_ring(geom: dict[str,Any]) -> list[list[float]]:
    c=geom["coordinates"]
    return c[0] if geom["type"]=="Polygon" else max((p[0] for p in c), key=len)

def main() -> int:
    params={"service":"WFS","version":"2.0.0","request":"GetFeature","typeNames":LAYER,"srsName":"EPSG:31370","bbox":f"{BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]},EPSG:31370","outputFormat":"application/json","count":"5000"}
    url=f"{WFS_URL}?{urllib.parse.urlencode(params)}"
    req=urllib.request.Request(url,headers={"User-Agent":"GrandBruxelles-Anneessens/1.0","Accept":"application/json"})
    with urllib.request.urlopen(req, timeout=120) as r: doc=json.loads(r.read().decode("utf-8"))
    matches=[f for f in doc.get("features",[]) if isinstance(f,dict) and contains(f.get("geometry",{}),ANCHOR_L72)]
    if len(matches)!=1: raise SystemExit(f"Expected exactly one official StreetSurfaces feature containing Anneessens anchor; got {len(matches)}")
    feature=matches[0]
    source_fc={"type":"FeatureCollection","features":[feature]}
    game=convert_document(source_fc, DEFAULT_ORIGIN_E, DEFAULT_ORIGIN_N, 0.0)
    ring=outer_ring(feature["geometry"]); c_l72=centroid_ring(ring); c_game=[c_l72[0]-DEFAULT_ORIGIN_E, -(c_l72[1]-DEFAULT_ORIGIN_N)]
    out={"schema":1,"source":{"authority":"Paradigm / Brussels-Capital Region","dataset":"UrbIS vector","license":"CC0","service":WFS_URL,"layer":LAYER,"request_url":url,"crs":"EPSG:31370","bbox":list(BBOX)},"production_anchor_game":list(ANCHOR_GAME),"production_anchor_l72":list(ANCHOR_L72),"placement_semantics":"official_surface_centroid_containing_production_anchor","surface_centroid_game":c_game,"surface":game["features"][0],"heritage":{"record":"Place Anneessens / Urban 10003005","authority":"urban.brussels architectural heritage inventory","facts":["rectangular square","central Francois Anneessens monument","white marble statue","blue-stone pedestal","inaugurated 1889","sculptor Thomas Vincotte"]},"representation":{"monument_dimensions_surveyed":False,"monument_geometry":"semantic_proxy"}}
    OUT.parent.mkdir(parents=True,exist_ok=True); OUT.write_text(json.dumps(out,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    print(f"ANNEESSENS_URBIS_SOURCE_OK centroid_game={c_game[0]:.3f},{c_game[1]:.3f} feature={feature.get('id','unknown')}")
    return 0
if __name__=="__main__": raise SystemExit(main())
