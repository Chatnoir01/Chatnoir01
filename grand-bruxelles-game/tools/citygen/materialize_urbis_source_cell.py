#!/usr/bin/env python3
"""Materialize one missing regional source cell from official UrbIS Buildings WFS.

Writes authoritative source plus a fail-closed maturity sidecar. No Godot/runtime
geometry is created or promoted here.
"""
from __future__ import annotations

import argparse, hashlib, json, math, sys, time, urllib.parse, urllib.request
from pathlib import Path
from typing import Any, Callable

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path: sys.path.insert(0, str(TOOLS_DIR))
from bootstrap_cell_maturity import build as build_maturity

CRS="EPSG:31370"; WFS_URL="https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"; LAYER="urbisvector:Buildings"; USER_AGENT="Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)"; CELL_SIZE=500.0


def digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()


def _token(value: float) -> str:
    return str(int(round(value))) if math.isclose(value,round(value),abs_tol=1e-8) else f"{value:.3f}".rstrip("0").rstrip(".").replace(".","p")


def canonical_cell_id(e: float,n: float,size: float=CELL_SIZE) -> str: return f"bxl-e{_token(e)}-n{_token(n)}-s{_token(size)}"


def parse_bbox(raw: str) -> tuple[float,float,float,float]:
    parts=tuple(float(v.strip()) for v in raw.split(","))
    if len(parts)!=4: raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    if not(parts[0]<parts[2] and parts[1]<parts[3]): raise argparse.ArgumentTypeError("invalid bbox extent")
    return parts


def _validate(cell_id: str,bbox: tuple[float,float,float,float]) -> None:
    min_e,min_n,max_e,max_n=bbox
    if min(bbox)<10_000: raise ValueError("bbox does not look like EPSG:31370 metres")
    if not math.isclose(max_e-min_e,CELL_SIZE,abs_tol=1e-6) or not math.isclose(max_n-min_n,CELL_SIZE,abs_tol=1e-6): raise ValueError("source materializer only accepts canonical 500 m cells")
    expected=canonical_cell_id(min_e,min_n,CELL_SIZE)
    if cell_id!=expected: raise ValueError(f"cell id/bbox mismatch: expected {expected}, got {cell_id}")


def _centroid(feature: dict[str,Any]) -> tuple[float,float] | None:
    geom=feature.get("geometry") or {}; coords=geom.get("coordinates") or []
    if geom.get("type")!="Polygon" or not coords or not isinstance(coords[0],list): return None
    points=[]
    for p in coords[0]:
        if not isinstance(p,list) or len(p)<2: return None
        x,y=float(p[0]),float(p[1])
        if not math.isfinite(x) or not math.isfinite(y): return None
        points.append((x,y))
    if len(points)>=2 and points[0]==points[-1]: points.pop()
    if len(points)<3: return None
    twice_area=0.0; cx=0.0; cy=0.0
    for i,(x0,y0) in enumerate(points):
        x1,y1=points[(i+1)%len(points)]; cross=x0*y1-x1*y0; twice_area+=cross; cx+=(x0+x1)*cross; cy+=(y0+y1)*cross
    if abs(twice_area)<1e-9: return (sum(x for x,_ in points)/len(points),sum(y for _,y in points)/len(points))
    return (cx/(3.0*twice_area),cy/(3.0*twice_area))


def owner_cell(feature: dict[str,Any]) -> str | None:
    center=_centroid(feature)
    if center is None: return None
    return canonical_cell_id(math.floor(center[0]/CELL_SIZE)*CELL_SIZE,math.floor(center[1]/CELL_SIZE)*CELL_SIZE,CELL_SIZE)


def request_buildings(bbox: tuple[float,float,float,float],retries: int=4) -> dict[str,Any]:
    params={"service":"WFS","version":"2.0.0","request":"GetFeature","typeNames":LAYER,"outputFormat":"application/json","srsName":CRS,"bbox":f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]},{CRS}"}
    request=urllib.request.Request(WFS_URL+"?"+urllib.parse.urlencode(params),headers={"User-Agent":USER_AGENT,"Accept":"application/geo+json, application/json"}); last=None
    for attempt in range(1,max(1,retries)+1):
        try:
            with urllib.request.urlopen(request,timeout=90) as response: payload=json.loads(response.read().decode("utf-8"))
            if payload.get("type")!="FeatureCollection": raise RuntimeError("unexpected UrbIS Buildings WFS payload")
            return payload
        except Exception as exc:
            last=exc
            if attempt<max(1,retries): time.sleep(min(12,2**attempt))
    raise RuntimeError(f"failed to fetch official Buildings layer: {last}")


def _write(path: Path,value: dict[str,Any],compact: bool) -> None:
    path.parent.mkdir(parents=True,exist_ok=True); text=json.dumps(value,ensure_ascii=False,separators=(",",":")) if compact else json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True); path.write_text(text+"\n",encoding="utf-8")


def materialize(cell_id: str,bbox: tuple[float,float,float,float],output_dir: Path,fetcher: Callable[[tuple[float,float,float,float]],dict[str,Any]]) -> dict[str,Any]:
    _validate(cell_id,bbox); document=fetcher(bbox)
    if not isinstance(document,dict) or document.get("type")!="FeatureCollection": raise ValueError("fetcher did not return a FeatureCollection")
    kept=[]; ownership_filtered=0; invalid_ownership=0
    for feature in document.get("features") or []:
        owner=owner_cell(feature)
        if owner is None: kept.append(feature); invalid_ownership+=1
        elif owner==cell_id: kept.append(feature)
        else: ownership_filtered+=1
    kept.sort(key=lambda f:str((f.get("properties") or {}).get("INSPIRE_ID") or f.get("id") or digest(f)))
    source={k:v for k,v in document.items() if k!="features"}; source["type"]="FeatureCollection"; source["features"]=kept; source["numberReturned"]=len(kept); source["grand_bruxelles_source"]={"authority":"Paradigm / Brussels-Capital Region","service":WFS_URL,"layer":LAYER,"crs":CRS,"bbox":list(bbox),"cell_id":cell_id,"ownership":"polygon_centroid_global_500m_cell"}
    _write(output_dir/"raw"/"buildings.geojson",source,True)
    manifest={"format":"grand-bruxelles-urbis-source-cell-v1","cell_id":cell_id,"crs":CRS,"bbox":list(bbox),"layers":{"buildings":{"wfs_name":LAYER,"features":len(kept),"ownership_filtered":ownership_filtered,"invalid_ownership_features":invalid_ownership,"file":"raw/buildings.geojson"}},"promotion":"source_only_no_runtime_mutation"}; manifest["source_digest"]=digest(manifest); _write(output_dir/"manifest.json",manifest,False)
    maturity=build_maturity(output_dir); _write(output_dir/"maturity.json",maturity,False)
    return manifest


def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("--cell-id",required=True); ap.add_argument("--bbox",type=parse_bbox,required=True); ap.add_argument("--output-dir",type=Path,required=True); ap.add_argument("--retries",type=int,default=4); args=ap.parse_args()
    manifest=materialize(args.cell_id,args.bbox,args.output_dir,lambda bbox:request_buildings(bbox,args.retries)); print(f"MATERIALIZE_URBIS_SOURCE_CELL_OK cell={args.cell_id} features={manifest['layers']['buildings']['features']} filtered={manifest['layers']['buildings']['ownership_filtered']} digest={manifest['source_digest']}"); return 0

if __name__=="__main__": raise SystemExit(main())
