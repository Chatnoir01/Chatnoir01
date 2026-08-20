#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, json, urllib.parse, urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
WFS = "https://data.mobility.brussels/geoserver/bm_urbis_topo/wfs"
CRS = "EPSG:31370"
PAD = 8.0
TARGET = {"CR63L","BR0101L","BR0102L","BR0103L","BR0104L","BR0105L","BR01L","BR02L","BR13L"}
SURFACES = (
    "data/urbis/bourse_street_surfaces.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_22982.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_41098.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_41084.game.json",
    "data/urbis/bourse_street_surfaces_adjacent_21944.game.json",
)
SIDEWALKS = "data/urbis/bourse_official_sidewalks.game.json"


def fetch(url: str) -> tuple[bytes,str]:
    req = urllib.request.Request(url, headers={"User-Agent":"grand-bruxelles-game-source-audit/1.0"})
    with urllib.request.urlopen(req, timeout=45) as r:
        b = r.read()
    return b, hashlib.sha256(b).hexdigest()


def bbox() -> tuple[float,float,float,float]:
    xs, ys = [], []
    for rel in SURFACES:
        p = json.loads((ROOT/rel).read_text())
        for s in p.get("surfaces",[]):
            if int(s.get("level",999)) != 0: continue
            for ring in s.get("source_rings_epsg31370",[]):
                for x,y in ring: xs.append(float(x)); ys.append(float(y))
    if not xs: raise RuntimeError("no Bourse source rings")
    return min(xs)-PAD,min(ys)-PAD,max(xs)+PAD,max(ys)+PAD


def capabilities() -> tuple[list[str],str,str]:
    q = urllib.parse.urlencode({"service":"WFS","version":"2.0.0","request":"GetCapabilities"})
    url = f"{WFS}?{q}"; raw, sha = fetch(url); root = ET.fromstring(raw)
    names = []
    for ft in root.iter():
        if ft.tag.split("}")[-1] != "FeatureType": continue
        for child in ft:
            if child.tag.split("}")[-1] == "Name" and child.text:
                names.append(child.text.strip()); break
    return names,sha,url


def get_features(layer: str, box: tuple[float,float,float,float]) -> tuple[dict[str,Any],str,str]:
    q = urllib.parse.urlencode({
        "service":"WFS","version":"2.0.0","request":"GetFeature","typeNames":layer,
        "srsName":CRS,"bbox":",".join(f"{v:.3f}" for v in box)+f",{CRS}",
        "outputFormat":"application/json","count":5000,
    })
    url = f"{WFS}?{q}"; raw,sha = fetch(url); data = json.loads(raw.decode())
    if data.get("type") != "FeatureCollection": raise RuntimeError(f"bad WFS payload {layer}")
    return data,sha,url


def strings(v: Any):
    if isinstance(v,str): yield v
    elif isinstance(v,dict):
        for x in v.values(): yield from strings(x)
    elif isinstance(v,list):
        for x in v: yield from strings(x)
    elif v is not None: yield str(v)


def codes(props: dict[str,Any]) -> list[str]:
    return sorted({s.strip().upper() for s in strings(props) if s.strip().upper() in TARGET})


def lines(geom: Any) -> list[list[list[float]]]:
    if not isinstance(geom,dict): return []
    c,t = geom.get("coordinates"),geom.get("type")
    raw = [c] if t == "LineString" else list(c or []) if t == "MultiLineString" else []
    out=[]
    for ln in raw:
        pts=[[float(p[0]),float(p[1])] for p in ln if isinstance(p,list) and len(p)>=2]
        if len(pts)>=2: out.append(pts)
    return out


def sidewalks() -> list[tuple[str,list[list[float]]]]:
    p=json.loads((ROOT/SIDEWALKS).read_text()); out=[]
    for s in p.get("sidewalks",[]):
        rings=s.get("source_rings_epsg31370",[])
        if rings: out.append((str(s.get("source_id","")),[[float(x),float(y)] for x,y in rings[0]]))
    if not out: raise RuntimeError("no committed Bourse sidewalks")
    return out


def orient(a,b,c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def onseg(a,b,p,e=1e-8): return min(a[0],b[0])-e<=p[0]<=max(a[0],b[0])+e and min(a[1],b[1])-e<=p[1]<=max(a[1],b[1])+e and abs(orient(a,b,p))<=e

def segx(a,b,c,d):
    o1,o2,o3,o4=orient(a,b,c),orient(a,b,d),orient(c,d,a),orient(c,d,b); e=1e-8
    if ((o1>e and o2<-e) or (o1<-e and o2>e)) and ((o3>e and o4<-e) or (o3<-e and o4>e)): return True
    return (abs(o1)<=e and onseg(a,b,c)) or (abs(o2)<=e and onseg(a,b,d)) or (abs(o3)<=e and onseg(c,d,a)) or (abs(o4)<=e and onseg(c,d,b))


def inside(p,ring):
    if any(onseg(ring[i],ring[i+1],p) for i in range(len(ring)-1)): return True
    x,y=p; hit=False
    for i in range(len(ring)-1):
        a,b=ring[i],ring[i+1]
        if (a[1]>y)!=(b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: hit=not hit
    return hit


def intersects(ln,ring):
    if any(inside(p,ring) for p in ln): return True
    return any(segx(ln[i],ln[i+1],ring[j],ring[j+1]) for i in range(len(ln)-1) for j in range(len(ring)-1))


def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("--output",type=Path,required=True); a=ap.parse_args()
    box=bbox(); sw=sidewalks(); fts,capsha,capurl=capabilities()
    line_layers=[n for n in fts if n.split(":")[-1].endswith("_line") or n.split(":")[-1] in {"barrier","railing"}]
    queries=[]; matched=[]; accepted=[]
    for layer in line_layers:
        fc,sha,url=get_features(layer,box); feats=fc.get("features",[])
        queries.append({"layer":layer,"feature_count_in_bbox":len(feats),"response_sha256":sha,"request_url":url})
        for f in feats:
            props=f.get("properties",{}); c=codes(props)
            if not c: continue
            ls=lines(f.get("geometry")); ids=sorted({sid for sid,ring in sw if any(intersects(ln,ring) for ln in ls)})
            item={"layer":layer,"feature_id":str(f.get("id","")),"target_topo_types":c,"properties":props,"source_lines_epsg31370":ls,"intersects_sidewalk_source_ids":ids}
            matched.append(item)
            if ids: accepted.append(item)
    out={
        "schema":"grand-bruxelles-bourse-a1-curb-alignment-spatial-evidence-v2","publisher":"Brussels Mobility / Paradigm",
        "workspace":"bm_urbis_topo","wfs_url":WFS,"capabilities_url":capurl,"capabilities_sha256":capsha,"crs":CRS,
        "existing_bourse_envelope_bbox_epsg31370":list(box),"envelope_pad_m":PAD,"advertised_feature_type_count":len(fts),
        "queried_line_like_feature_type_count":len(line_layers),"target_topo_types":sorted(TARGET),"committed_sidewalk_source_ids":[x[0] for x in sw],
        "layer_queries":queries,"matched_target_feature_count":len(matched),"sidewalk_intersecting_target_feature_count":len(accepted),
        "matched_target_features":matched,"sidewalk_intersecting_target_features":accepted,
        "physical_curb_height_supported":False,"vertical_extrusion_allowed":False,"curb_elevation_resolved":False,"runtime_approved":False,"realism_complete":False,
    }
    a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(out,ensure_ascii=False,indent=2)+"\n")
    print(f"BOURSE_A1_CURB_SPATIAL_EVIDENCE layers={len(line_layers)} matched={len(matched)} sidewalk_intersections={len(accepted)} bbox={box}")
    for x in accepted: print("BOURSE_A1_CURB_SOURCE_MATCH",x["layer"],x["feature_id"],",".join(x["target_topo_types"]),",".join(x["intersects_sidewalk_source_ids"]))
    if not accepted:
        print("BOURSE_A1_CURB_SPATIAL_FAIL: no official target line intersects committed Bourse sidewalks")
        return 1
    return 0

if __name__ == "__main__": raise SystemExit(main())
