#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,os,re,tempfile,time,urllib.error,urllib.parse,urllib.request,zipfile
from collections import defaultdict
from pathlib import Path
import shapefile
from pyproj import Transformer
from shapely.geometry import shape as shp_shape
from shapely.ops import transform,unary_union
from shapely.prepared import prep

WFS=(
 "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs",
 "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/ows",
 "https://geoservices-urbis.irisnet.be/geoserver/ows",
)
LAYER="urbisvector:Buildings"; CRS="EPSG:31370"; PAGE=5000
URL_ID=re.compile(r"https?://databrussels\.be/id/building/(\d+)",re.I)
RAW_ID=re.compile(r"(?<!\d)(\d{4,10})(?!\d)")
NAMED_ID=re.compile(r"(?:building_2d_id|building_id|urbis_building_id|source_building_id|bu_id)\s*[\"']?\s*[:=]\s*[\"']?(\d+)",re.I)
OFFICIAL_KEYS={"building_2d_id","building_id","urbis_building_id","source_building_id","bu_id"}
GP={"1601883","1601884","1608847","1608851","1611166","1613517","1635455","1635485","1637695","1637729","1639985","1643344","1645578","1645580","1646728","1647834","1647943","1649069","1653185","1661439","1781508"}
B01_03={"anderlecht-E145500_N169000-B01","anderlecht-E145500_N169000-B02","anderlecht-E145500_N169000-B03"}

def get(url,token=""):
 h={"User-Agent":"Grand-Bruxelles-1000-Counter/2.0","Accept":"*/*"}
 if token:h.update({"Authorization":f"Bearer {token}","Accept":"application/vnd.github+json","X-GitHub-Api-Version":"2022-11-28"})
 last=None
 for n in range(4):
  try:
   with urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=180) as r:return r.read()
  except urllib.error.HTTPError as e:
   last=RuntimeError(f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:1200]}")
   if e.code<500 and e.code!=429:break
  except Exception as e:last=e
  time.sleep(min(2**n,8))
 raise RuntimeError(f"GET failed {url}: {last}")

def digest(ids):return hashlib.sha256(("\n".join(ids)+"\n").encode()).hexdigest()
def rcsv(p):
 with p.open(encoding="utf-8",newline="") as f:return list(csv.DictReader(f))
def batch_ids(r):return [x for x in r["building_ids"].split(";") if x]

def postal_boundary(path,expected_sha):
 raw=path.read_bytes(); actual=hashlib.sha256(raw).hexdigest()
 if actual!=expected_sha:raise RuntimeError(f"postal archive drift {actual} != {expected_sha}")
 candidates=[]
 with zipfile.ZipFile(path) as z,tempfile.TemporaryDirectory() as d:
  z.extractall(d)
  for p in Path(d).rglob("*.shp"):
   try:r=shapefile.Reader(str(p),encoding="utf-8",encodingErrors="replace")
   except Exception:continue
   fields=[x[0] for x in r.fields[1:]]; base=5*("post" in p.name.lower())+sum(2 for f in fields if "post" in f.lower() or "zip" in f.lower())
   for sr in r.iterShapeRecords():
    if sr.shape.shapeType not in {5,15,25,31}:continue
    vals=sr.record.as_dict(); keys=[k for k,v in vals.items() if str(v).strip()=="1000"]
    if not keys:continue
    try:g=shp_shape(sr.shape.__geo_interface__)
    except Exception:continue
    if g.is_empty:continue
    score=base+max(5 if ("post" in k.lower() or "zip" in k.lower()) else 1 for k in keys)
    candidates.append((score,p.name,g))
 if not candidates:raise RuntimeError("NGI archive has no postcode 1000 polygon")
 best=max(x[0] for x in candidates); candidates=[x for x in candidates if x[0]==best]; names={x[1] for x in candidates}
 if len(names)!=1:raise RuntimeError(f"ambiguous NGI postcode layer {names}")
 geom=unary_union([x[2] for x in candidates]); tr=Transformer.from_crs("EPSG:4326",CRS,always_xy=True); geom=transform(tr.transform,geom)
 if geom.is_empty or not geom.is_valid:raise RuntimeError("invalid 1000 boundary")
 return geom,{"archive_sha256":actual,"shapefile":next(iter(names)),"feature_count":len(candidates),"bounds":list(geom.bounds),"area_m2":geom.area}

def owner_id(f):
 p=f.get("properties") or {}
 for k,v in p.items():
  if k.lower() in OFFICIAL_KEYS|{"id","inspire_id"}:
   m=URL_ID.search(str(v))
   if m:return m.group(1)
   if str(v).strip().isdigit():return str(int(str(v).strip()))
 m=URL_ID.search(json.dumps(p))
 if m:return m.group(1)
 m=re.search(r"(?:Buildings?|building)[._:/-](\d+)$",str(f.get("id","")),re.I)
 return m.group(1) if m else None

def page(endpoint,q):
 d=json.loads(get(endpoint+"?"+urllib.parse.urlencode(q)))
 if not isinstance(d,dict) or not isinstance(d.get("features"),list):raise RuntimeError("WFS did not return GeoJSON")
 return d

def official_buildings(boundary):
 b=boundary.bounds; bbox=f"{b[0]:.3f},{b[1]:.3f},{b[2]:.3f},{b[3]:.3f}"; common={"service":"WFS","request":"GetFeature","outputformat":"json"}; errors=[]; chosen=None
 profiles=[]
 for ep in WFS:
  profiles += [(ep,{**common,"version":"2.0.0","typename":LAYER,"srsName":CRS,"bbox":bbox+","+CRS,"count":str(PAGE)},"wfs2-crs-bbox"),(ep,{**common,"version":"2.0.0","typename":LAYER,"srsName":CRS,"bbox":bbox,"count":str(PAGE)},"wfs2-native-bbox")]
 for ep,q,label in profiles:
  try:probe=page(ep,q);chosen=(ep,q,label,probe);break
  except Exception as e:errors.append(f"{label}@{ep}: {e}")
 if not chosen:raise RuntimeError("all UrbIS WFS profiles failed: "+" | ".join(errors))
 ep,base,label,probe=chosen; fs=probe["features"]; keys=list((fs[0].get("properties") or {}).keys()); lower={k.lower():k for k in keys}; sort=None
 for k in ("bu_id","building_id","building_2d_id","urbis_building_id","source_building_id","objectid","gid","fid","id","inspire_id"):
  if k in lower:
   candidate=lower[k]; vals=[str((x.get("properties") or {}).get(candidate)) for x in fs]
   if len(vals)==len(set(vals)) and all(v not in {"","None"} for v in vals):sort=candidate;break
 if not sort:
  for candidate in keys:
   if "id" not in candidate.lower():continue
   vals=[str((x.get("properties") or {}).get(candidate)) for x in fs]
   if len(vals)==len(set(vals)) and all(v not in {"","None"} for v in vals):sort=candidate;break
 if not sort:raise RuntimeError(f"no stable WFS sort field in {keys}")
 base=dict(base);base["sortBy"]=sort; prepared=prep(boundary); owners={}; start=0; pages=0; fetched=0; matched=None; prior=None
 while True:
  q=dict(base)
  if start:q["startIndex"]=str(start)
  d=page(ep,q); fs=d["features"]; pages+=1; fetched+=len(fs)
  if matched is None:matched=d.get("numberMatched",d.get("totalFeatures"))
  sig=hashlib.sha256(json.dumps([(f.get("id"),(f.get("properties") or {}).get(sort)) for f in fs[:8]],sort_keys=True,default=str).encode()).hexdigest() if fs else None
  if start and fs and sig==prior:raise RuntimeError(f"WFS repeated page {start}")
  prior=sig
  for f in fs:
   if not f.get("geometry"):continue
   g=shp_shape(f["geometry"]); p=g.representative_point()
   if not prepared.covers(p):continue
   oid=owner_id(f)
   if not oid:raise RuntimeError(f"building without official owner id: {f.get('id')}")
   owners.setdefault(oid,(p.x,p.y))
  if len(fs)<PAGE:break
  start+=len(fs)
  if pages>100:raise RuntimeError("WFS pagination runaway")
 if isinstance(matched,(int,float)) and int(matched)!=fetched:raise RuntimeError(f"WFS truncated matched={matched} fetched={fetched}")
 ordered=sorted(owners,key=int)
 return owners,{"profile":label,"endpoint":ep,"version":base["version"],"sort_field":sort,"pages":pages,"bbox_features":fetched,"number_matched":matched,"owners":len(owners),"owner_sha256":digest(ordered)}

def campaigns(plan,c01,c02):
 batches=rcsv(plan/"source_batches.csv"); assigns=rcsv(plan/"missing_owner_assignments.csv"); by={r["building_id"]:r for r in assigns}
 def clean(x,mun,rev):
  r=by.get(x)
  return bool(r and r["assignment_status"]=="assigned" and r["municipality_slug"]==mun and r["revision_dates"]==rev and ";" not in r["distribution_keys"])
 a=[]; rev=c01["source"]["revision"]
 for b in batches:
  if b["assignment_status"]=="assigned" and b["municipality_slug"]=="anderlecht" and b["batch_id"] not in B01_03:
   for x in batch_ids(b):
    if not clean(x,"anderlecht",rev):raise RuntimeError(f"C01 planner drift {x}")
    a.append(x)
 for b in batches:
  if len(a)>=30000:break
  if b["assignment_status"]=="assigned" and b["municipality_slug"]=="bruxelles":
   for x in batch_ids(b):
    if len(a)>=30000:break
    if x not in GP and clean(x,"bruxelles",rev):a.append(x)
 if len(a)!=30000 or digest(a)!=c01["expected"]["owner_sequence_sha256"]:raise RuntimeError("C01 reproduction mismatch")
 aset=set(a); b2=[]; rev=c02["source"]["revision"]
 for mun in ("bruxelles","uccle"):
  for b in batches:
   if len(b2)>=30000:break
   if b["assignment_status"]=="assigned" and b["municipality_slug"]==mun:
    for x in batch_ids(b):
     if len(b2)>=30000:break
     if x in aset or (mun=="bruxelles" and x in GP):continue
     if clean(x,mun,rev):b2.append(x)
  if len(b2)>=30000:break
 if len(b2)!=30000 or digest(b2)!=c02["expected"]["owner_sequence_sha256"] or aset&set(b2):raise RuntimeError("C02 reproduction mismatch")
 return aset,set(b2),{r["building_id"] for r in assigns}

def numeric(v):
 if isinstance(v,int):return str(v)
 if not isinstance(v,str):return None
 v=v.strip()
 if v.isdigit():return v
 m=URL_ID.fullmatch(v);return m.group(1) if m else None

def structured(payload,official):
 out=set(); stack=[payload]
 while stack:
  n=stack.pop()
  if isinstance(n,dict):
   for k,v in n.items():
    kl=str(k).lower()
    if kl in OFFICIAL_KEYS or ("urbis" in kl and "building" in kl):
     x=numeric(v)
     if x in official:out.add(x)
    if isinstance(v,(dict,list)):stack.append(v)
  elif isinstance(n,list):stack.extend(n)
 return out

def exact_file_ids(path,official):
 try:t=path.read_text(encoding="utf-8")
 except (OSError,UnicodeDecodeError):return set()
 out=set(URL_ID.findall(t))|set(NAMED_ID.findall(t))
 if path.suffix.lower() in {".json",".geojson"}:
  try:out|=structured(json.loads(t),official)
  except json.JSONDecodeError:pass
 return out&official

def repo_sets(root,official):
 source=set(); runtime=set(); urbis=root/"grand-bruxelles-game/data/urbis"
 if urbis.exists():
  for p in urbis.rglob("*"):
   if p.is_file() and p.suffix.lower() in {".json",".geojson"}:source|=exact_file_ids(p,official)
 for base in (root/"grand-bruxelles-game/game/scripts",root/"grand-bruxelles-game/data/runtime"):
  if not base.exists():continue
  for p in base.rglob("*"):
   if p.is_file() and p.suffix.lower() in {".gd",".tscn",".tres",".cfg",".json",".geojson"}:runtime|=exact_file_ids(p,official)
 main_scene=root/"grand-bruxelles-game/game/main.tscn"
 if main_scene.exists():runtime|=exact_file_ids(main_scene,official)
 return source,runtime

def pr_sets(official,ignore):
 token=os.getenv("GITHUB_TOKEN",""); repo=os.getenv("GITHUB_REPOSITORY",""); head=os.getenv("GITHUB_HEAD_REF",""); out=defaultdict(set)
 if not token or not repo:return {}
 def api(path):return json.loads(get("https://api.github.com"+path,token))
 page_no=1
 while True:
  prs=api(f"/repos/{repo}/pulls?state=open&per_page=100&page={page_no}")
  if not prs:break
  for pr in prs:
   n=int(pr["number"]); branch=(pr.get("head") or {}).get("ref",""); text=str(pr.get("title") or "")+"\n"+str(pr.get("body") or ""); low=text.lower()
   if n==ignore or branch==head or any(s in low for s in ("source-only","source only","planning only","evidence-only","diagnostic-only","qa/planning only")):continue
   for x in set(URL_ID.findall(text))|set(RAW_ID.findall(text)):
    if x in official:out[x].add(n)
   files=api(f"/repos/{repo}/pulls/{n}/files?per_page=100")
   for f in files:
    patch=str(f.get("filename") or "")+"\n"+str(f.get("patch") or "")
    for x in set(URL_ID.findall(patch))|set(NAMED_ID.findall(patch))|set(RAW_ID.findall(patch)):
     if x in official:out[x].add(n)
  if len(prs)<100:break
  page_no+=1
 return {k:sorted(v) for k,v in out.items()}

def main():
 ap=argparse.ArgumentParser()
 for n in ("repo-root","contract","planner-dir","ngi-postal-zip","c01-contract","c02-contract","output-json","output-csv"):ap.add_argument("--"+n,type=Path,required=True)
 a=ap.parse_args(); c=json.loads(a.contract.read_text()); expected=c["expected_inventory"]
 boundary,bmeta=postal_boundary(a.ngi_postal_zip,expected["postal_archive_sha256"]); owners,wmeta=official_buildings(boundary)
 if wmeta["owners"]!=expected["official_building_owner_total"] or wmeta["owner_sha256"]!=expected["owner_sha256"]:raise RuntimeError(f"1000 inventory drift {wmeta}")
 official=set(owners); c01,c02,planner_missing=campaigns(a.planner_dir,json.loads(a.c01_contract.read_text()),json.loads(a.c02_contract.read_text())); source,runtime=repo_sets(a.repo_root,official); prs=pr_sets(official,int(c["campaigns"]["active_source_draft_pr"]))
 finished=set(); ledger=a.repo_root/"grand-bruxelles-game/data/qa/bruxelles_1000_building_completion_ledger.json"
 if ledger.exists():
  for e in json.loads(ledger.read_text()).get("owners",[]):
   if e.get("status")=="finished_perfect" and str(e.get("building_id")) in official:finished.add(str(e["building_id"]))
 counts=defaultdict(int); rows=[]
 for x in sorted(official,key=int):
  if x in finished:s="finished_perfect"
  elif x in prs:s="started_open_pr"
  elif x in runtime:s="started_main_runtime"
  elif x in c01 or x in source:s="source_registered_main"
  elif x in c02:s="source_draft"
  elif x in planner_missing:s="unstarted"
  else:s="unresolved"
  counts[s]+=1; rows.append({"building_id":x,"status":s,"open_prs":";".join(map(str,prs.get(x,[]))),"runtime_main":str(x in runtime).lower(),"source_main":str(x in source).lower(),"c01":str(x in c01).lower(),"c02":str(x in c02).lower(),"planner_missing":str(x in planner_missing).lower(),"x":f"{owners[x][0]:.3f}","y":f"{owners[x][1]:.3f}"})
 order=["finished_perfect","started_open_pr","started_main_runtime","source_registered_main","source_draft","unstarted","unresolved"]; total=len(official)
 if sum(counts[k] for k in order)!=total:raise RuntimeError("accounting drift")
 report={"schema":"grand-bruxelles-postcode-building-counter-v2","scope":c["scope"],"production_base_sha":c["production_base_sha"],"postal_boundary":{**c["postal_boundary"],**bmeta},"buildings":{**c["building_source"],**wmeta},"counts":{"official_building_owner_total":total,**{k:counts[k] for k in order},"remaining_to_perfect":total-len(finished)},"evidence":{"planner_missing_inside_1000":len(official&planner_missing),"c01_inside_1000":len(official&c01),"c02_inside_1000":len(official&c02),"source_main_exact":len(source),"runtime_main_exact":len(runtime),"open_pr_exact":len(prs)},"status_rules":c["status_rules"],"runtime_authorized":False,"geometry_modified":False}
 a.output_json.parent.mkdir(parents=True,exist_ok=True);a.output_json.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
 with a.output_csv.open("w",encoding="utf-8",newline="") as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 print("BRUXELLES_1000_BUILDING_COUNTER_OK "+json.dumps(report["counts"],sort_keys=True)+" evidence="+json.dumps(report["evidence"],sort_keys=True))
if __name__=="__main__":main()
