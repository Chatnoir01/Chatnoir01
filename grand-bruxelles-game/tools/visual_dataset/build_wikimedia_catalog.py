#!/usr/bin/env python3
"""Build a deterministic, license-gated Brussels visual reference catalog.
Metadata-first by design: binaries are downloaded only with --download-dir.
"""
from __future__ import annotations
import argparse, hashlib, json, urllib.parse, urllib.request
from pathlib import Path
ALLOWED={"CC0","Public domain","CC BY 4.0","CC BY-SA 4.0","CC BY 3.0","CC BY-SA 3.0","CC BY 2.0","CC BY-SA 2.0"}
API="https://commons.wikimedia.org/w/api.php"
def api(params):
 q=urllib.parse.urlencode({"format":"json","formatversion":2,**params}); req=urllib.request.Request(API+"?"+q,headers={"User-Agent":"GrandBruxellesGameVisualDataset/1.0"}); return json.load(urllib.request.urlopen(req,timeout=30))
def clean(v):
 if isinstance(v,dict): return v.get("value","")
 return v or ""
def query(limit):
 params={"action":"query","generator":"geosearch","ggsprimary":"all","ggsnamespace":6,"ggsradius":10000,"ggscoord":"50.8503|4.3517","ggslimit":min(limit,500),"prop":"imageinfo|coordinates","iiprop":"url|extmetadata|sha1|mime|size","iiurlwidth":1600}
 return api(params).get("query",{}).get("pages",[])
def record(p):
 ii=(p.get("imageinfo") or [{}])[0]; meta=ii.get("extmetadata",{}); coords=(p.get("coordinates") or [{}])[0]; lic=clean(meta.get("LicenseShortName")); url=ii.get("thumburl") or ii.get("url","")
 return {"pageid":p.get("pageid"),"title":p.get("title"),"lat":coords.get("lat"),"lon":coords.get("lon"),"url":url,"description_url":ii.get("descriptionurl"),"author":clean(meta.get("Artist")),"credit":clean(meta.get("Credit")),"license":lic,"license_url":clean(meta.get("LicenseUrl")),"date_time":clean(meta.get("DateTimeOriginal")) or clean(meta.get("DateTime")),"mime":ii.get("mime"),"width":ii.get("width"),"height":ii.get("height"),"commons_sha1":ii.get("sha1"),"accepted":bool(url and lic in ALLOWED)}
def download(r,root):
 data=urllib.request.urlopen(urllib.request.Request(r["url"],headers={"User-Agent":"GrandBruxellesGameVisualDataset/1.0"}),timeout=60).read(); sha=hashlib.sha256(data).hexdigest(); ext=Path(urllib.parse.urlparse(r["url"]).path).suffix.lower() or ".img"; out=root/(sha+ext); out.write_bytes(data); r["sha256"]=sha; r["local_file"]=out.name
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--limit",type=int,default=500); ap.add_argument("--output",required=True); ap.add_argument("--download-dir"); a=ap.parse_args(); rows=sorted((record(p) for p in query(a.limit)),key=lambda r:(r["pageid"] or 0,r["title"] or "")); accepted=[r for r in rows if r["accepted"]]
 if a.download_dir:
  root=Path(a.download_dir); root.mkdir(parents=True,exist_ok=True)
  for r in accepted: download(r,root)
 payload={"format":"grand-bruxelles-visual-catalog-v1","source":"Wikimedia Commons geosearch","license_allowlist":sorted(ALLOWED),"summary":{"seen":len(rows),"accepted":len(accepted),"quarantined":len(rows)-len(accepted)},"images":rows}; Path(a.output).write_text(json.dumps(payload,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8"); print("VISUAL_CATALOG_OK",payload["summary"])
if __name__=="__main__": main()
