#!/usr/bin/env python3
"""Collect public KartaView street-level references across Brussels."""
from __future__ import annotations
import argparse, json, urllib.parse, urllib.request
from pathlib import Path
API="https://api.openstreetcam.org/2.0/photo/"
LATS=(50.79,50.83,50.87,50.91)
LONS=(4.27,4.33,4.39,4.45)
DEFAULT_POINTS=[(lat,lon) for lat in LATS for lon in LONS]
def fetch(params):
 req=urllib.request.Request(API+"?"+urllib.parse.urlencode(params),headers={"User-Agent":"GrandBruxellesGameVisualDataset/1.2"})
 with urllib.request.urlopen(req,timeout=45) as r: return json.load(r)
def candidate_lists(obj):
 out=[]
 if isinstance(obj,list): out.append(obj)
 elif isinstance(obj,dict):
  for v in obj.values(): out.extend(candidate_lists(v))
 return out
def extract_rows(payload):
 lists=[x for x in candidate_lists(payload) if x and isinstance(x[0],dict)]
 return max(lists,key=len) if lists else []
def first(d,*keys):
 for k in keys:
  if d.get(k) not in (None,""): return d.get(k)
 return None
def normalize(item):
 lat=first(item,"lat","latitude","gpsLat"); lon=first(item,"lng","lon","longitude","gpsLng")
 return {"source":"KartaView","source_id":str(first(item,"id","photoId","photo_id") or ""),"lat":float(lat) if lat is not None else None,"lon":float(lon) if lon is not None else None,"captured_at":first(item,"dateAdded","dateProcessed","timestamp","createdAt"),"heading":first(item,"heading","direction","gpsHeading"),"sequence_id":str(first(item,"sequenceId","sequence_id") or ""),"url":first(item,"fileUrlProc","fileurlProc","imageUrl","url","name"),"usage_class":"REFERENCE_ONLY"}
def query_point(lat,lon,max_per_point):
 payload=fetch({"lat":lat,"lng":lon,"zoomLevel":15,"join":"sequence","orderBy":"id","orderDirection":"desc"})
 return extract_rows(payload)[:max_per_point]
def collect(points,max_per_point=150):
 seen={}; successful=0
 for lat,lon in points:
  rows=query_point(lat,lon,min(max_per_point,150)); successful+=1
  for raw in rows:
   row=normalize(raw); key=row["source_id"] or json.dumps(row,sort_keys=True); seen[key]=row
 return sorted(seen.values(),key=lambda x:(x["source_id"],x["lat"] or 0,x["lon"] or 0)),successful
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--output",required=True); ap.add_argument("--max-per-point",type=int,default=150); a=ap.parse_args(); rows,successful=collect(DEFAULT_POINTS,a.max_per_point)
 status="ok" if rows else "NO_COVERAGE"
 payload={"format":"grand-bruxelles-kartaview-catalog-v1","status":status,"query_points":DEFAULT_POINTS,"summary":{"queries":successful,"images":len(rows),"geolocated":sum(x["lat"] is not None and x["lon"] is not None for x in rows)},"images":rows}; Path(a.output).write_text(json.dumps(payload,indent=2,sort_keys=True)+"\n",encoding="utf-8"); print("KARTAVIEW_CATALOG_"+status,payload["summary"])
if __name__=="__main__": main()
