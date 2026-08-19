#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,os,re,time,urllib.request
from collections import defaultdict
from pathlib import Path

URL_ID=re.compile(r"https?://databrussels\.be/id/building/(\d+)",re.I)
RAW_ID=re.compile(r"(?<!\d)(\d{4,10})(?!\d)")
NAMED_ID=re.compile(r"(?:building_2d_id|building_id|urbis_building_id|source_building_id|bu_id)\s*[\"']?\s*[:=]\s*[\"']?(\d+)",re.I)
OFFICIAL_KEYS={"building_2d_id","building_id","urbis_building_id","source_building_id","bu_id"}
TEXT_EXTS={".gd",".tscn",".tres",".cfg",".md",".json",".geojson"}

def http_json(url:str):
 token=os.getenv("GITHUB_TOKEN","")
 req=urllib.request.Request(url,headers={"User-Agent":"Grand-Bruxelles-1000-Counter-Refiner/1.0","Accept":"application/vnd.github+json","Authorization":f"Bearer {token}"} if token else {"User-Agent":"Grand-Bruxelles-1000-Counter-Refiner/1.0"})
 with urllib.request.urlopen(req,timeout=120) as r:return json.loads(r.read())

def numeric(value):
 if isinstance(value,int):return str(value)
 if not isinstance(value,str):return None
 value=value.strip()
 if value.isdigit():return value
 m=URL_ID.fullmatch(value)
 return m.group(1) if m else None

def structured_ids(payload,official:set[str]):
 found=set(); stack=[payload]
 while stack:
  node=stack.pop()
  if isinstance(node,dict):
   for k,v in node.items():
    kl=str(k).lower()
    if kl in OFFICIAL_KEYS or ("urbis" in kl and "building" in kl):
     x=numeric(v)
     if x in official:found.add(x)
    if isinstance(v,(dict,list)):stack.append(v)
  elif isinstance(node,list):stack.extend(node)
 return found

def exact_ids_from_file(path:Path,official:set[str]):
 try:text=path.read_text(encoding="utf-8")
 except (UnicodeDecodeError,OSError):return set()
 found=set(URL_ID.findall(text))|set(NAMED_ID.findall(text))
 if path.suffix.lower() in {".json",".geojson"}:
  try:found|=structured_ids(json.loads(text),official)
  except json.JSONDecodeError:pass
 return found&official

def source_refs(root:Path,official:set[str]):
 found=set(); base=root/"grand-bruxelles-game"/"data"
 if not base.exists():return found
 for p in base.rglob("*"):
  if not p.is_file() or p.suffix.lower() not in {".json",".geojson"}:continue
  rel=p.relative_to(base).as_posix()
  if rel.startswith("runtime/") or rel.startswith("qa/bruxelles_1000_building_counter"):continue
  found|=exact_ids_from_file(p,official)
 return found

def runtime_refs(root:Path,official:set[str]):
 found=set()
 roots=[root/"grand-bruxelles-game"/"game",root/"grand-bruxelles-game"/"data"/"runtime"]
 for base in roots:
  if not base.exists():continue
  for p in base.rglob("*"):
   if p.is_file() and p.suffix.lower() in TEXT_EXTS:found|=exact_ids_from_file(p,official)
 return found

def open_pr_refs(official:set[str],ignore:int):
 repo=os.getenv("GITHUB_REPOSITORY",""); head=os.getenv("GITHUB_HEAD_REF","")
 if not repo or not os.getenv("GITHUB_TOKEN"):return {}
 out=defaultdict(set); page=1
 while True:
  pulls=http_json(f"https://api.github.com/repos/{repo}/pulls?state=open&per_page=100&page={page}")
  if not pulls:break
  for pr in pulls:
   n=int(pr["number"]); branch=(pr.get("head") or {}).get("ref","")
   body=(str(pr.get("title") or "")+"\n"+str(pr.get("body") or "")); low=body.lower()
   if n==ignore or branch==head or any(x in low for x in ("source-only","source only","planning only","evidence-only","qa/planning only","diagnostic-only")):continue
   for x in set(URL_ID.findall(body))|set(RAW_ID.findall(body)):
    if x in official:out[x].add(n)
   fp=1
   while True:
    files=http_json(f"https://api.github.com/repos/{repo}/pulls/{n}/files?per_page=100&page={fp}")
    if not files:break
    for f in files:
     blob=str(f.get("filename") or "")+"\n"+str(f.get("patch") or "")
     for x in set(URL_ID.findall(blob))|set(NAMED_ID.findall(blob))|set(RAW_ID.findall(blob)):
      if x in official:out[x].add(n)
    if len(files)<100:break
    fp+=1
   time.sleep(0.01)
  if len(pulls)<100:break
  page+=1
 return {k:sorted(v) for k,v in out.items()}

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--repo-root",type=Path,required=True);ap.add_argument("--contract",type=Path,required=True);ap.add_argument("--json",type=Path,required=True);ap.add_argument("--csv",type=Path,required=True);a=ap.parse_args()
 contract=json.loads(a.contract.read_text()); report=json.loads(a.json.read_text())
 with a.csv.open(encoding="utf-8",newline="") as f:rows=list(csv.DictReader(f))
 official={r["building_id"] for r in rows}; source=source_refs(a.repo_root,official); runtime=runtime_refs(a.repo_root,official); prs=open_pr_refs(official,int(contract["campaigns"]["active_source_draft_pr"]))
 ledger=a.repo_root/"grand-bruxelles-game/data/qa/bruxelles_1000_building_completion_ledger.json"; finished=set()
 if ledger.exists():
  for e in json.loads(ledger.read_text()).get("owners",[]):
   if e.get("status")=="finished_perfect" and str(e.get("building_id")) in official:finished.add(str(e["building_id"]))
 counts=defaultdict(int)
 for r in rows:
  x=r["building_id"]
  if x in finished:s="finished_perfect"
  elif x in prs:s="started_open_pr"
  elif x in runtime:s="started_main_runtime"
  elif r.get("c01")=="true" or x in source:s="source_registered_main"
  elif r.get("c02")=="true":s="source_draft"
  elif r.get("planner_missing")=="true":s="unstarted"
  else:s="unresolved"
  r["status"]=s;r["open_prs"]=";".join(map(str,prs.get(x,[])));r["source_main_exact"]=str(x in source).lower();r["runtime_main_exact"]=str(x in runtime).lower();counts[s]+=1
 total=len(rows); ordered=["finished_perfect","started_open_pr","started_main_runtime","source_registered_main","source_draft","unstarted","unresolved"]
 if sum(counts[k] for k in ordered)!=total:raise RuntimeError("refined accounting drift")
 report["counts"]={"official_building_owner_total":total,**{k:counts[k] for k in ordered},"remaining_to_perfect":total-len(finished)}
 report["evidence"].update({"repo_source_refs_exact":len(source),"repo_runtime_refs_exact":len(runtime),"open_pr_refs_exact":len(prs)})
 report["classification_revision"]="exact-structured-main-runtime-v2"
 report["status_rules"]=contract["status_rules"]
 a.json.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
 fields=list(rows[0].keys())
 with a.csv.open("w",encoding="utf-8",newline="") as f:w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
 print("BRUXELLES_1000_REFINED_COUNTER_OK "+json.dumps(report["counts"],sort_keys=True)+f" source_exact={len(source)} runtime_exact={len(runtime)} pr_exact={len(prs)}")
if __name__=="__main__":main()
