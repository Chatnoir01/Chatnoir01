#!/usr/bin/env python3
"""Build a deterministic Brussels Commons reference catalog with full pagination.

Discovery is performed once, then deterministic download shards reuse that catalog.
Downloads are deliberately polite: transient upstream failures are retried with
Retry-After/exponential backoff; genuinely unavailable sources remain indexed.
"""
from __future__ import annotations
import argparse, hashlib, json, time, urllib.parse, urllib.request
from urllib.error import HTTPError, URLError
from pathlib import Path
API="https://commons.wikimedia.org/w/api.php"
REUSABLE={"CC0","Public domain","CC BY 4.0","CC BY-SA 4.0","CC BY 3.0","CC BY-SA 3.0","CC BY 2.0","CC BY-SA 2.0"}
USER_AGENT="GrandBruxellesGameVisualDataset/1.4 (+https://github.com/Chatnoir01/Chatnoir01)"
def retry_delay(exc,attempt):
 value=getattr(exc,'headers',{}).get('Retry-After') if getattr(exc,'headers',None) else None
 try: return min(180.0,max(1.0,float(value))) if value else min(120.0,2.0**attempt)
 except ValueError: return min(120.0,2.0**attempt)
def api(params,retries=8):
 q=urllib.parse.urlencode({"format":"json","formatversion":2,**params}); req=urllib.request.Request(API+"?"+q,headers={"User-Agent":USER_AGENT}); last=None
 for attempt in range(retries):
  try: return json.load(urllib.request.urlopen(req,timeout=45))
  except HTTPError as exc:
   last=exc
   if exc.code!=429 and exc.code<500: raise
   time.sleep(retry_delay(exc,attempt))
  except (URLError,TimeoutError) as exc:
   last=exc; time.sleep(min(60.0,2.0**attempt))
 if last: raise last
 raise RuntimeError('Commons API retry loop exhausted')
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
def download(r,root,retries=9):
 last=None
 for attempt in range(retries):
  try:
   req=urllib.request.Request(r["url"],headers={"User-Agent":USER_AGENT}); data=urllib.request.urlopen(req,timeout=90).read(); sha=hashlib.sha256(data).hexdigest(); ext=Path(urllib.parse.urlparse(r["url"]).path).suffix.lower() or ".img"; out=root/(sha+ext); out.write_bytes(data); r.update({"sha256":sha,"local_file":out.name,"download_bytes":len(data),"download_state":"DOWNLOADED"}); time.sleep(0.35); return "DOWNLOADED"
  except HTTPError as exc:
   last=f'HTTPError {exc.code}: {exc.reason}'
   if exc.code in {404,410}:
    r.update({"download_state":"UNAVAILABLE_SOURCE","download_error":last}); return "UNAVAILABLE_SOURCE"
   if exc.code==429 or exc.code>=500:
    time.sleep(retry_delay(exc,attempt)); continue
   r.update({"download_state":"UNAVAILABLE_SOURCE","download_error":last}); return "UNAVAILABLE_SOURCE"
  except (URLError,TimeoutError,OSError) as exc:
   last=f'{type(exc).__name__}: {exc}'; time.sleep(min(90.0,2.0**attempt))
 r.update({"download_state":"TRANSIENT_FAILURE","download_error":last}); return "TRANSIENT_FAILURE"
def load_rows(a):
 if a.catalog_input:
  source=json.loads(Path(a.catalog_input).read_text(encoding='utf-8')); rows=source.get('images',[])
  if source.get('format') not in {'grand-bruxelles-visual-catalog-v2','grand-bruxelles-visual-catalog-v3'}: raise SystemExit('unsupported catalog input format')
  return sorted(rows,key=lambda r:(r.get('pageid') or 0,r.get('title') or ''))
 return sorted((record(p) for p in query_all(a.max_images)),key=lambda r:(r["pageid"] or 0,r["title"] or ""))
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--max-images",type=int,default=0); ap.add_argument("--output",required=True); ap.add_argument("--download-dir"); ap.add_argument('--catalog-input'); ap.add_argument('--shard-count',type=int,default=1); ap.add_argument('--shard-index',type=int,default=0); a=ap.parse_args()
 if a.shard_count<1 or not 0<=a.shard_index<a.shard_count: raise SystemExit('invalid shard configuration')
 if a.catalog_input and a.max_images: raise SystemExit('--max-images cannot be combined with --catalog-input')
 all_rows=load_rows(a); rows=[dict(r) for r in all_rows if stable_shard(r,a.shard_count)==a.shard_index]; reusable=[r for r in rows if r["usage_class"]=="REUSABLE_ASSET_SOURCE"]
 downloaded=unavailable=transient=download_bytes=0
 if a.download_dir:
  root=Path(a.download_dir); root.mkdir(parents=True,exist_ok=True)
  for r in rows:
   if not r.get("url"): continue
   state=download(r,root)
   if state=="DOWNLOADED": downloaded+=1; download_bytes+=int(r.get('download_bytes',0))
   elif state=="UNAVAILABLE_SOURCE": unavailable+=1
   else: transient+=1
 payload={"format":"grand-bruxelles-visual-catalog-v3","source":"Wikimedia Commons geosearch","reusable_license_allowlist":sorted(REUSABLE),"shard":{"index":a.shard_index,"count":a.shard_count},"summary":{"global_seen":len(all_rows),"seen":len(rows),"reusable":len(reusable),"reference_only":len(rows)-len(reusable),"downloadable":sum(bool(r.get('url')) for r in rows),"downloaded":downloaded,"unavailable_sources":unavailable,"transient_failures":transient,"download_failures":unavailable+transient,"download_bytes":download_bytes},"images":rows}; Path(a.output).write_text(json.dumps(payload,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8"); print("VISUAL_CATALOG_OK",payload["summary"])
if __name__=="__main__": main()
