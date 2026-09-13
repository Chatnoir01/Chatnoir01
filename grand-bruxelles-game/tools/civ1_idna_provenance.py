#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
from urllib.parse import urlsplit

SCHEMA="grand-bruxelles-civ1-idna-provenance-v1"

class DuplicateJSONKeyError(ValueError): pass
class NonStandardJSONConstantError(ValueError): pass

def _pairs(pairs):
    out={}
    for k,v in pairs:
        if k in out: raise DuplicateJSONKeyError(k)
        out[k]=v
    return out

def _constant(token): raise NonStandardJSONConstantError(token)

def idna_host_reasons(source_url: str):
    reasons=[]
    try: host=(urlsplit(source_url).hostname or "")
    except ValueError: return ["source_url_invalid"]
    for label in host.split("."):
        if not label.startswith("xn--"): continue
        try:
            decoded=label.encode("ascii").decode("idna")
            roundtrip=decoded.encode("idna").decode("ascii").lower()
        except (UnicodeError,UnicodeDecodeError,UnicodeEncodeError):
            reasons.append("source_url_idna_label_invalid"); continue
        if roundtrip!=label.lower(): reasons.append("source_url_idna_label_invalid")
    return sorted(set(reasons))

def inspect_registry(registry_path: Path):
    try:
        registry=json.loads(registry_path.read_text(encoding="utf-8"),object_pairs_hook=_pairs,parse_constant=_constant)
    except (OSError,json.JSONDecodeError,DuplicateJSONKeyError,NonStandardJSONConstantError):
        return {"schema":SCHEMA,"blocking_reasons":["registry_unreadable_or_invalid_json"],"registration_count":0,"invalid_count":0,"entries":[]}
    entries=registry.get("entries",[]) if isinstance(registry,dict) else []
    if not isinstance(entries,list):
        return {"schema":SCHEMA,"blocking_reasons":["entries_not_array"],"registration_count":0,"invalid_count":0,"entries":[]}
    results=[]
    for entry in entries:
        source=entry.get("source_url") if isinstance(entry,dict) else None
        reasons=idna_host_reasons(source) if isinstance(source,str) else ["source_url_missing"]
        results.append({"source_url":source,"valid":not reasons,"blocking_reasons":reasons})
    invalid=[e for e in results if not e["valid"]]
    return {"schema":SCHEMA,"blocking_reasons":["invalid_idna_provenance_present"] if invalid else [],"registration_count":len(entries),"invalid_count":len(invalid),"entries":results,"source_url_idna_alabel_roundtrip_required":True,"runtime_authorized":False,"visual_approval_claimed":False}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("registry",type=Path); ap.add_argument("--out",type=Path)
    a=ap.parse_args(); payload=inspect_registry(a.registry)
    text=json.dumps(payload,indent=2,sort_keys=True)+"\n"
    if a.out:
        a.out.parent.mkdir(parents=True,exist_ok=True); a.out.write_text(text,encoding="utf-8")
    print(json.dumps(payload,sort_keys=True))
    return 2 if payload["blocking_reasons"] else 0

if __name__=="__main__": raise SystemExit(main())
