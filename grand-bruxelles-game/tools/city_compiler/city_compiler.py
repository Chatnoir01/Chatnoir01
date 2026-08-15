#!/usr/bin/env python3
"""Fail-closed deterministic Brussels mass-generation candidate compiler."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any
FORMAT="grand-bruxelles-city-compiler-v1"
REQUIRED_CRS="EPSG:31370"
REQUIRED_GATES=("runtime_geometry","collisions","streaming","terrain","heights","performance")
def digest(v:Any)->str:
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
def validate(cell:dict[str,Any])->dict[str,Any]:
    reasons=[]
    if cell.get("crs")!=REQUIRED_CRS: reasons.append("crs_not_epsg31370")
    b=cell.get("bbox")
    if not isinstance(b,list) or len(b)!=4 or not all(isinstance(x,(int,float)) for x in b) or not (b[0]<b[2] and b[1]<b[3]): reasons.append("invalid_bbox")
    p=cell.get("provenance",{})
    if p.get("source_records_present") is not True or not p.get("primary"): reasons.append("missing_provenance")
    g=cell.get("geometry",{})
    if g.get("authoritative_geometry_ready") is not True or not g.get("source_manifest"): reasons.append("authoritative_geometry_not_ready")
    gates=cell.get("maturity",{}).get("gates",{})
    reasons += [f"gate_{n}_not_passed" for n in REQUIRED_GATES if gates.get(n) is not True]
    if cell.get("heights",{}).get("status") in {None,"unknown","invalidated"}: reasons.append("height_evidence_not_accepted")
    state="approved" if not reasons else "quarantine"
    return {"cell_id":cell.get("cell_id","unknown"),"state":state,"grade":"A" if state=="approved" else "D","reasons":sorted(set(reasons)),"source_digest":digest(cell)}
def compile_cells(root:Path)->dict[str,Any]:
    cells=[]
    for path in sorted(root.glob("*.json")):
        cell=json.loads(path.read_text(encoding="utf-8")); result=validate(cell); result["source"]=path.as_posix(); cells.append(result)
    summary={"processed":len(cells),"approved":sum(c["state"]=="approved" for c in cells),"quarantined":sum(c["state"]=="quarantine" for c in cells)}
    out={"format":FORMAT,"summary":summary,"cells":cells}; out["generation_digest"]=digest(out); return out
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--input",default="grand-bruxelles-game/data/cell_manifests"); ap.add_argument("--output"); a=ap.parse_args(); out=compile_cells(Path(a.input)); text=json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+"\n"
    if a.output: Path(a.output).write_text(text,encoding="utf-8")
    else: print(text,end="")
    return 0
if __name__=="__main__": raise SystemExit(main())
