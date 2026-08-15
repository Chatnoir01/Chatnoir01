#!/usr/bin/env python3
"""Collect public KartaView street-level references around Brussels."""
from __future__ import annotations
import argparse, json, urllib.parse, urllib.request
from pathlib import Path
API="https://api.openstreetcam.org/2.0/photo/"
DEFAULT_POINTS=[(50.8353,4.3358),(50.8467,4.3525),(50.8503,4.3488),(50.8468,4.3499)]
def fetch(params):
 req=urllib.request.Request(API+"?"+urllib.parse.urlencode(params),headers={"User-Agent":"GrandBruxellesGameVisualDataset/1.1"})
 with urllib.request.urlopen(req,timeout=45) as r: return json.load(r)
def candidate_lists(obj):
 out=[]
 if isinstance(obj,list): out.append(obj)
 elif isinstance(obj,dict):
  for v in obj.values(): out.extend(candidate_lists(v))
 return out
def extract_rows(payload):
 lists=[x for x in candidate_lists(payload) if x and isinstance(x[0],dict)]
 if not lists: return []
 return max(lists,key=len)
def first(d,*keys):
 for k in keys:
  if d.get(k) not in (None,""): return d.get(k)
 return None
def normalize(item):
 lat=first(item,"lat","latitude","gpsLat"); lon=first(item,"lng","lon","longitude","gpsLng")
 return {"source":"KartaView","source_id":str(first(item,"id","photoId","photo_id") or ""),"lat":float(lat) if lat is not None else None,"lon":float(lon) if lon is not None else None,"captured_at":first(item,"dateAdded","dateProcessed","timestamp","createdAt"),"heading":first(item,"heading","direction","gpsHeading"),"sequence_id":str(first(item,"sequenceId","sequence_id") or ""),"url":first(item,"fileUrlProc","fileurlProc","imageUrl","url","name"),"usage_class":"REFERENCE_ONLY"}
def query_point(lat,lon,max_per_point):
 # KartaView's documented public nearby-photo form uses lat/lng/radius.
 payload=fetch({"lat":lat,"lng":lon,"radius":5000})
 rows=extract_rows(payload)
 if not rows:
  # Keep compatibility with the documented map-click form as a fallback.
  payload=fetch({"lat":lat,"lng":lon,"zoomLevel":15,"join":"sequence","orderBy":"id","orderDirection":"desc"})
  rows=extract_rows(payload)
 return rows[:max_per_point]
def collect(points,max_per_point=150):
 seen={}
 for lat,lon in points:
  for raw in query_point(lat,lon,min(max_per_point,150)):
   row=normalize(raw); key=row["source_id"] or json.dumps(row,sort_keys=True)
   seen[key]=row
 return sorted(seen.values(),key=lambda x:(x["source_id"],x["lat"] or 0,x["lon"] or 0))
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--output",required=True); ap.add_argument("--max-per-point",type=int,default=150); a=ap.parse_args(); rows=collect(DEFAULT_POINTS,a.max_per_point)
 payload={"format":"grand-bruxelles-kartaview-catalog-v1","status":"ok","query_points":DEFAULT_POINTS,"summary":{"images":len(rows),"geolocated":sum(x["lat"] is not None and x["lon"] is not None for x in rows)},"images":rows}; Path(a.output).write_text(json.dumps(payload,indent=2,sort_keys=True)+"\n",encoding="utf-8"); print("KARTAVIEW_CATALOG_OK",payload["summary"])
if __name__=="__main__": main()
