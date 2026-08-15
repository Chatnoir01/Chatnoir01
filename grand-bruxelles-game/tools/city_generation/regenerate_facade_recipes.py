#!/usr/bin/env python3
"""Regenerate corrected facade recipes deterministically and prove geometry immutability."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('rules',HERE/'apply_facade_rules.py')
rules=importlib.util.module_from_spec(SPEC); assert SPEC.loader is not None; SPEC.loader.exec_module(rules)

def digest(v):
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

def geometry_digest(recipe):
    return digest(recipe.get('geometry') or {})

def regenerate(payload):
    first=rules.apply(payload)
    second=rules.apply(payload)
    if first != second:
        raise ValueError('non_deterministic_rule_application')
    source_by_id={str(r.get('building_id')):r for r in payload.get('recipes') or []}
    rows=[]
    for corrected in first.get('recipes') or []:
        bid=str(corrected.get('building_id'))
        source=source_by_id.get(bid)
        if source is None:
            raise ValueError(f'missing_source_recipe:{bid}')
        before=geometry_digest(source); after=geometry_digest(corrected)
        if before != after:
            raise ValueError(f'geometry_mutated:{bid}')
        state='REGEN_READY_FOR_RUNTIME_QA' if corrected.get('state')=='CORRECTED_CANDIDATE' else 'QUARANTINE'
        rows.append({'building_id':bid,'state':state,'geometry_digest':after,'corrected_digest':corrected.get('corrected_digest'),'style_recipe':corrected.get('style_recipe') or {},'reasons':corrected.get('reasons') or [],'correction':corrected.get('correction') or {}})
    rows.sort(key=lambda r:r['building_id'])
    out={'format':'grand-bruxelles-facade-regeneration-v1','rule_version':'facade-correction-v1','summary':{'recipes':len(rows),'runtime_qa_ready':sum(r['state']=='REGEN_READY_FOR_RUNTIME_QA' for r in rows),'quarantined':sum(r['state']=='QUARANTINE' for r in rows)},'recipes':rows}
    out['regeneration_digest']=digest(out)
    return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--output',required=True); a=ap.parse_args(); payload=json.loads(Path(a.input).read_text(encoding='utf-8')); out=regenerate(payload); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('FACADE_REGENERATION_OK',out['summary'],out['regeneration_digest'])
if __name__=='__main__': main()
