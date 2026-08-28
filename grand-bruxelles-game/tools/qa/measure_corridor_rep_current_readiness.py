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
        out[key]=sorted(int(v) for v in out.get(key,[]))
    return out


def expectation_for(contract, mode):
    if mode=='historical':
        return normalized_expected(contract['expected'])
    if mode=='corrected-pair-current':
        return normalized_expected(contract['current_corrected_pair_expected'])
    raise AssertionError(f'unsupported expectation mode: {mode}')


def validate_measurement_base(contract, measurement_base_sha):
    evidence_base=contract['production_base_sha']
    assert isinstance(evidence_base,str) and len(evidence_base)==40
    assert isinstance(measurement_base_sha,str) and len(measurement_base_sha)==40
    if measurement_base_sha==evidence_base:
        return evidence_base
    assert contract['status']=='LOCKED_EVIDENCE_ONLY'
    assert contract['policy']['semantic_lock_survives_clean_live_main_rebuild'] is True
    locked=contract['locked_evidence']
    assert locked['production_base_sha']==evidence_base
    assert len(locked['semantic_sha256'])==64
    assert len(locked['measurement_sha256'])==64
    return evidence_base


def indexed_readiness(readiness, expected_source_sha):
    destinations=readiness['destinations']
    assert readiness['destination_count']==len(destinations)
    assert all(v is False for v in readiness['authorization'].values())
    ids=[int(r['road_osm_id']) for r in destinations]
    assert len(ids)==len(set(ids)), 'duplicate road_osm_id in readiness catalog'
    for row in destinations:
        assert row['source_license']=='ODbL-1.0'
        assert row['source_sha256']==expected_source_sha
        assert row['readiness']=='REGISTERED_NOT_RENDERED'
        for key in ('render_authorized','collision_authorized','runtime_mount_authorized','safe_spawn_authorized','jouable_authorized'):
            assert row[key] is False
    return {int(r['road_osm_id']):r for r in destinations}


def measure(contract, reps, readiness, production_base_sha, expectation_mode):
    validate_measurement_base(contract,production_base_sha)
    assert contract['source']['license']=='ODbL-1.0'
    assert all(v is False for v in contract['authorization'].values())
    assert reps['status']=='LOCKED_REPRESENTATIVE_EVIDENCE_ONLY'
    assert reps['locked_evidence']['semantic_sha256']==contract['source']['representative_semantic_sha256']
    current=indexed_readiness(readiness,contract['source']['road_source_sha256'])
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
    assert accounting==expectation_for(contract,expectation_mode)
    if expectation_mode=='historical':
        out={'schema':'grand-bruxelles-corrected-frame-corridor-representative-current-readiness-v1','status':'HOLD_ATOMIC_MIGRATION_BEFORE_RUNTIME_PROBE','production_base_sha':production_base_sha,'accounting':accounting,'representatives':rows,'authorization':contract['authorization']}
    else:
        out={'schema':'grand-bruxelles-corrected-frame-corridor-representative-current-readiness-v1','status':'REGISTERED_TARGET_CELLS_HOLD_RENDER_COLLISION','expectation_mode':'corrected-pair-current','production_base_sha':production_base_sha,'accounting':accounting,'representatives':rows,'authorization':contract['authorization']}
    basis=dict(out); basis.pop('production_base_sha'); out['semantic_sha256']=digest(basis)
    return out


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--contract',required=True)
    ap.add_argument('--representatives',required=True)
    ap.add_argument('--readiness',required=True)
    ap.add_argument('--production-base-sha',required=True)
    ap.add_argument('--expectation-mode',choices=('historical','corrected-pair-current'),default='historical')
    ap.add_argument('--output',required=True)
    a=ap.parse_args()
    out=measure(load(a.contract),load(a.representatives),load(a.readiness),a.production_base_sha,a.expectation_mode)
    Path(a.output).write_text(json.dumps(out,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('CORRIDOR_REP_CURRENT_READINESS_OK',a.expectation_mode,out['semantic_sha256'])

if __name__=='__main__': main()
