#!/usr/bin/env python3
"""Build deterministic QA work queues from a mass candidate manifest.

READY_FOR_QA buildings are always included. Quarantined buildings are sampled
reproducibly per cell so systemic rule failures remain visible without flooding
human review. This stage does not claim visual approval and never promotes runtime.
"""
from __future__ import annotations
import argparse, hashlib, json
from collections import Counter, defaultdict
from pathlib import Path

def score_id(value:str)->int:
    return int(hashlib.sha256(value.encode()).hexdigest()[:16],16)

def build(payload,quarantine_sample_per_cell=3):
    if payload.get('format')!='grand-bruxelles-mass-candidate-manifest-v1': raise ValueError('unsupported manifest format')
    ready=[]; quarantined=defaultdict(list); reason_counts=Counter(); cells=Counter()
    for row in payload.get('buildings') or []:
        bid=str(row.get('building_id')); cell=str(row.get('cell_id')); cells[cell]+=1
        if row.get('state')=='READY_FOR_QA':
            problems=[]
            if int(row.get('vertex_count') or 0)<4: problems.append('invalid_vertex_count')
            area=row.get('area_m2')
            if area is not None and float(area)<=0: problems.append('non_positive_area')
            if not row.get('recipe_digest'): problems.append('recipe_digest_missing')
            ready.append({'building_id':bid,'cell_id':cell,'priority':'MANDATORY','preflight':'FAIL' if problems else 'PASS','problems':problems,'candidate_digest':row.get('candidate_digest')})
        else:
            reasons=row.get('reasons') or ['unknown_quarantine_reason']
            for reason in reasons: reason_counts[str(reason)]+=1
            quarantined[cell].append({'building_id':bid,'cell_id':cell,'priority':'QUARANTINE_SAMPLE','reasons':sorted(set(map(str,reasons))),'candidate_digest':row.get('candidate_digest')})
    ready.sort(key=lambda x:(x['cell_id'],x['building_id']))
    sampled=[]
    for cell,rows in sorted(quarantined.items()):
        rows=sorted(rows,key=lambda x:(score_id(x['building_id']),x['building_id']))
        sampled.extend(rows[:quarantine_sample_per_cell])
    queue=ready+sampled
    summary={'authoritative_buildings':sum(cells.values()),'mandatory_ready':len(ready),'mandatory_preflight_failures':sum(x['preflight']=='FAIL' for x in ready),'quarantine_sampled':len(sampled),'cells':len(cells),'queue_items':len(queue)}
    out={'format':'grand-bruxelles-candidate-qa-queue-v1','status':'PRE_VISUAL_QA_ONLY','runtime_promotion_allowed':False,'summary':summary,'cell_counts':dict(sorted(cells.items())),'quarantine_reason_counts':dict(sorted(reason_counts.items())),'queue':queue}
    out['queue_digest']=hashlib.sha256(json.dumps(out,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest(); return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--manifest',required=True); ap.add_argument('--output',required=True); ap.add_argument('--quarantine-sample-per-cell',type=int,default=3); a=ap.parse_args()
    if a.quarantine_sample_per_cell<0: raise SystemExit('sample must be >= 0')
    payload=json.loads(Path(a.manifest).read_text(encoding='utf-8')); out=build(payload,a.quarantine_sample_per_cell); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('CANDIDATE_QA_QUEUE_OK',out['summary'],out['queue_digest']); return 2 if out['summary']['mandatory_preflight_failures'] else 0
if __name__=='__main__': raise SystemExit(main())
