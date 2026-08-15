#!/usr/bin/env python3
"""Mapillary street-level reference connector for Grand Bruxelles.

Uses the official Graph API only. Live collection requires MAPILLARY_ACCESS_TOKEN.
The connector is metadata/reference oriented and never promotes imagery into runtime.
"""
from __future__ import annotations
import argparse, json, os, urllib.parse, urllib.request
from pathlib import Path

API="https://graph.mapillary.com/images"
DEFAULT_BBOX=(4.24,50.76,4.50,50.93)  # Brussels-region working envelope, lon/lat
FIELDS="id,captured_at,computed_geometry,compass_angle,thumb_2048_url,sequence"

def normalize(item):
    geom=item.get("computed_geometry") or {}
    coords=geom.get("coordinates") or [None,None]
    return {
        "source":"Mapillary",
        "source_id":str(item.get("id","")),
        "lat":coords[1] if len(coords)>1 else None,
        "lon":coords[0] if coords else None,
        "captured_at":item.get("captured_at"),
        "heading":item.get("compass_angle"),
        "sequence_id":((item.get("sequence") or {}).get("id") if isinstance(item.get("sequence"),dict) else item.get("sequence")),
        "url":item.get("thumb_2048_url"),
        "usage_class":"REFERENCE_ONLY",
    }

def fetch_page(token,bbox,after=None,limit=1000):
    params={"bbox":",".join(str(v) for v in bbox),"fields":FIELDS,"limit":min(limit,2000)}
    if after: params["after"]=after
    req=urllib.request.Request(API+"?"+urllib.parse.urlencode(params),headers={"Authorization":"OAuth "+token,"User-Agent":"GrandBruxellesGameVisualDataset/1.0"})
    with urllib.request.urlopen(req,timeout=45) as response: return json.load(response)

def collect(token,bbox,max_images=0):
    out=[]; after=None
    while True:
        payload=fetch_page(token,bbox,after)
        out.extend(normalize(x) for x in payload.get("data",[]))
        if max_images and len(out)>=max_images: return out[:max_images]
        paging=payload.get("paging") or {}; cursors=paging.get("cursors") or {}; nxt=cursors.get("after")
        if not nxt or nxt==after: return out
        after=nxt

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--output",required=True); ap.add_argument("--max-images",type=int,default=0); ap.add_argument("--bbox",default=",".join(str(v) for v in DEFAULT_BBOX)); ap.add_argument("--access-token",default=os.getenv("MAPILLARY_ACCESS_TOKEN","")); args=ap.parse_args()
    if not args.access_token:
        Path(args.output).write_text(json.dumps({"format":"grand-bruxelles-mapillary-catalog-v1","status":"BLOCKED_EXTERNAL_KEY","images":[]},indent=2)+"\n",encoding="utf-8")
        print("MAPILLARY_CATALOG_BLOCKED_EXTERNAL_KEY")
        return 3
    bbox=tuple(float(v) for v in args.bbox.split(",")); rows=collect(args.access_token,bbox,args.max_images); rows=sorted(rows,key=lambda x:(x["source_id"],x.get("captured_at") or 0))
    payload={"format":"grand-bruxelles-mapillary-catalog-v1","status":"ok","bbox":bbox,"summary":{"images":len(rows),"geolocated":sum(x["lat"] is not None and x["lon"] is not None for x in rows)},"images":rows}
    Path(args.output).write_text(json.dumps(payload,indent=2,sort_keys=True)+"\n",encoding="utf-8"); print("MAPILLARY_CATALOG_OK",payload["summary"])
if __name__=="__main__": raise SystemExit(main())
