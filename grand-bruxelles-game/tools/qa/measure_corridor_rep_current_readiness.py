#!/usr/bin/env python3
import argparse, hashlib, json
from pathlib import Path


def load(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def digest(obj):
    raw=json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()


def normalized_expected(expected):
    out=dict(expected)
    for key in ('expected_absent_road_osm_ids','expected_wrong_cell_road_osm_ids'):
        out[key]=sorted(int(v) for v in out[key])
    return out


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--contract',required=True)
    ap.add_argument('--representatives',required=True)
    ap.add_argument('--readiness',required=True)
    ap.add_argument('--production-base-sha',required=True)
    ap.add_argument('--output',required=True)
    a=ap.parse_args()
    c=load(a.contract); reps=load(a.representatives); rd=load(a.readiness)
    assert c['production_base_sha']==a.production_base_sha
    assert c['source']['license']=='ODbL-1.0'
    assert all(v is False for v in c['authorization'].values())
    assert reps['status']=='LOCKED_REPRESENTATIVE_EVIDENCE_ONLY'
    assert reps['locked_evidence']['semantic_sha256']==c['source']['representative_semantic_sha256']
    assert rd['destination_count']==len(rd['destinations'])
    assert all(v is False for v in rd['authorization'].values())
    current={int(r['road_osm_id']):r for r in rd['destinations']}
    rows=[]; absent=[]; wrong=[]; correct=[]
    for t in reps['selection']['target_cells']:
        rid=int(t['expected_road_osm_id']); cur=current.get(rid); target=t['cell_id']
        if cur is None:
            state='ABSENT_FROM_CURRENT_READINESS'; absent.append(rid); cur_cell=None
        elif cur['cell_id']!=target:
            state='PRESENT_IN_HISTORICAL_CELL_WRONG_FOR_CORRECTED_FRAME'; wrong.append(rid); cur_cell=cur['cell_id']
        else:
            state='PRESENT_IN_TARGET_CELL_NOT_RENDERED'; correct.append(rid); cur_cell=cur['cell_id']
        rows.append({'anchor':t['anchor'],'road_osm_id':rid,'target_cell_id':target,'current_cell_id':cur_cell,'state':state,'runtime_probe_eligible':False})
    accounting={
      'representative_count':len(rows),
      'present_in_current_readiness_count':len(rows)-len(absent),
      'absent_from_current_readiness_count':len(absent),
      'present_but_wrong_cell_count':len(wrong),
      'present_in_target_cell_count':len(correct),
      'runtime_probe_eligible_count':0,
      'expected_absent_road_osm_ids':sorted(absent),
      'expected_wrong_cell_road_osm_ids':sorted(wrong)}
    assert accounting==normalized_expected(c['expected'])
    out={'schema':'grand-bruxelles-corrected-frame-corridor-representative-current-readiness-v1','status':'HOLD_ATOMIC_MIGRATION_BEFORE_RUNTIME_PROBE','production_base_sha':a.production_base_sha,'accounting':accounting,'representatives':rows,'authorization':c['authorization']}
    basis=dict(out); basis.pop('production_base_sha'); out['semantic_sha256']=digest(basis)
    Path(a.output).write_text(json.dumps(out,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('CORRIDOR_REP_CURRENT_READINESS_OK',out['semantic_sha256'])

if __name__=='__main__': main()
