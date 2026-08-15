#!/usr/bin/env python3
"""Build a deterministic Brussels Commons reference catalog with full pagination.

Optional sharding lets CI download the complete bank in parallel without changing
which references belong to the global catalog.
"""
from __future__ import annotations
import argparse, hashlib, json, time, urllib.parse, urllib.request
from pathlib import Path
API="https://commons.wikimedia.org/w/api.php"
REUSABLE={"CC0","Public domain","CC BY 4.0","CC BY-SA 4.0","CC BY 3.0","CC BY-SA 3.0","CC BY 2.0","CC BY-SA 2.0"}
USER_AGENT="GrandBruxellesGameVisualDataset/1.2"
def api(params):
 q=urllib.parse.urlencode({"format":"json","formatversion":2,**params}); req=urllib.request.Request(API+"?"+q,headers={"User-Agent":USER_AGENT}); return json.load(urllib.request.urlopen(req,timeout=30))
def clean(v): return v.get("value","") if isinstance(v,dict) else (v or "")
def query_all(max_images=0):
 rows=[]; cont={}
 while True:
  params={"action":"query","generator":"geosearch","ggsprimary":"all","ggsnamespace":6,"ggsradius":10000,"ggscoord":"50.8503|4.3517","ggslimit":500,"prop":"imageinfo|coordinates","iiprop":"url|extmetadata|sha1|mime|size","iiurlwidth":1600,**cont}
  data=api(params); rows.extend(data.get("query",{}).get("pages",[]))
  if max_images and len(rows)>=max_images: return rows[:max_images]
  if "continue" not in data: return rows
  cont=data["continue"]
def record(p):
 ii=(p.get("imageinfo") or [{}])[0]; meta=ii.get("extmetadata",{}); coords=(p.get("coordinates") or [{}])[0]; lic=clean(meta.get("LicenseShortName")); url=ii.get("thumburl") or ii.get("url","")
 return {"pageid":p.get("pageid"),"title":p.get("title"),"lat":coords.get("lat"),"lon":coords.get("lon"),"url":url,"description_url":ii.get("descriptionurl"),"author":clean(meta.get("Artist")),"credit":clean(meta.get("Credit")),"license":lic,"license_url":clean(meta.get("LicenseUrl")),"date_time":clean(meta.get("DateTimeOriginal")) or clean(meta.get("DateTime")),"mime":ii.get("mime"),"width":ii.get("width"),"height":ii.get("height"),"commons_sha1":ii.get("sha1"),"usage_class":"REUSABLE_ASSET_SOURCE" if url and lic in REUSABLE else "REFERENCE_ONLY"}
def stable_shard(row,count):
 raw=str(row.get('pageid') or row.get('title') or '').encode(); return int(hashlib.sha256(raw).hexdigest()[:16],16)%count
def download(r,root,retries=3):
 last=None
 for attempt in range(retries):
  try:
   data=urllib.request.urlopen(urllib.request.Request(r["url"],headers={"User-Agent":USER_AGENT}),timeout=60).read(); sha=hashlib.sha256(data).hexdigest(); ext=Path(urllib.parse.urlparse(r["url"]).path).suffix.lower() or ".img"; out=root/(sha+ext); out.write_bytes(data); r["sha256"]=sha; r["local_file"]=out.name; r["download_bytes"]=len(data); return True
  except Exception as exc:
   last=f'{type(exc).__name__}: {exc}'; time.sleep(1.5*(attempt+1))
 r['download_error']=last; return False
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--max-images",type=int,default=0,help="0 means exhaust API pagination"); ap.add_argument("--output",required=True); ap.add_argument("--download-dir"); ap.add_argument('--shard-count',type=int,default=1); ap.add_argument('--shard-index',type=int,default=0); a=ap.parse_args()
 if a.shard_count<1 or not 0<=a.shard_index<a.shard_count: raise SystemExit('invalid shard configuration')
 all_rows=sorted((record(p) for p in query_all(a.max_images)),key=lambda r:(r["pageid"] or 0,r["title"] or "")); rows=[r for r in all_rows if stable_shard(r,a.shard_count)==a.shard_index]; reusable=[r for r in rows if r["usage_class"]=="REUSABLE_ASSET_SOURCE"]
 downloaded=failures=download_bytes=0
 if a.download_dir:
  root=Path(a.download_dir); root.mkdir(parents=True,exist_ok=True)
  for r in rows:
   if not r["url"]: continue
   if download(r,root): downloaded+=1; download_bytes+=int(r.get('download_bytes',0))
   else: failures+=1
 payload={"format":"grand-bruxelles-visual-catalog-v3","source":"Wikimedia Commons geosearch","reusable_license_allowlist":sorted(REUSABLE),"shard":{"index":a.shard_index,"count":a.shard_count},"summary":{"global_seen":len(all_rows),"seen":len(rows),"reusable":len(reusable),"reference_only":len(rows)-len(reusable),"downloadable":sum(bool(r['url']) for r in rows),"downloaded":downloaded,"download_failures":failures,"download_bytes":download_bytes},"images":rows}; Path(a.output).write_text(json.dumps(payload,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8"); print("VISUAL_CATALOG_OK",payload["summary"])
if __name__=="__main__": main()
