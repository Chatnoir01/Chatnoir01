#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
KNOWN_BASELINE_PHASE=27
MATERIAL_PHASE_LIMIT=12

def assess(payload):
    if payload.get('schema')!='grand-bruxelles-civ1-time-local-phase-v1': raise ValueError('unexpected schema')
    if payload.get('godot_version')!='4.7.1': raise ValueError('Godot 4.7.1 evidence required')
    if payload.get('runtime_authorized') is not False or payload.get('visual_approval_claimed') is not False: raise ValueError('QA-only rails must remain closed')
    candidates=payload.get('candidates')
    if not isinstance(candidates,list) or len(candidates)<2: raise ValueError('at least two candidates required')
    seen=set(); rows=[]
    for c in candidates:
        if not isinstance(c,dict): raise ValueError('candidate must be object')
        cid=c.get('candidate_id')
        if not isinstance(cid,str) or not cid or cid.strip()!=cid or cid in seen: raise ValueError('candidate_id must be canonical and unique')
        seen.add(cid)
        if c.get('baseline_phase_delta_samples')!=KNOWN_BASELINE_PHASE: raise ValueError(f'{cid}: baseline phase must remain +27')
        phase=c.get('candidate_phase_delta_samples')
        if isinstance(phase,bool) or not isinstance(phase,int): raise ValueError(f'{cid}: phase must be integer')
        rows.append({'candidate_id':cid,'candidate_phase_delta_samples':phase,'phase_improved':abs(phase)<KNOWN_BASELINE_PHASE,'phase_materially_fixed':abs(phase)<MATERIAL_PHASE_LIMIT})
    improved=[r for r in rows if r['phase_improved']]
    materially_fixed=[r for r in rows if r['phase_materially_fixed']]
    if not improved:
        verdict='BLOCK_TIME_LOCAL_NO_PHASE_IMPROVEMENT'
    elif not materially_fixed:
        verdict='BLOCK_TIME_LOCAL_PHASE_STILL_MATERIAL'
    else:
        verdict='REQUIRE_FULL_GROUNDING_ASSESSMENT'
    return {'schema':'grand-bruxelles-civ1-time-local-phase-assessment-v1','verdict':verdict,'evaluated_candidates':rows,'runtime_authorized':False,'visual_approval_claimed':False}

def main():
    p=argparse.ArgumentParser(); p.add_argument('input',type=Path); p.add_argument('output',type=Path); a=p.parse_args(); result=assess(json.loads(a.input.read_text())); a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n'); print(result['verdict']); return 0
if __name__=='__main__': raise SystemExit(main())
