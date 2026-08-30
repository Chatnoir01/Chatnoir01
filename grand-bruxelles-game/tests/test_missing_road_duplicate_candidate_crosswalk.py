#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, json, math
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'data/qa/brussels_missing_road_source_artifact_lock.json'
CAT=ROOT/'data/qa/brussels_missing_road_duplicate_candidate_crosswalk.json'
HEX=set('0123456789abcdef')
CLOSED={'source_registration_authorized','road_cell_mapping_authorized','render_authorized','collision_authorized','runtime_mount_authorized','safe_spawn_authorized','jouable_authorized'}
DECISION={'municipality_assignment_authorized':False,'spatial_cell_assignment_authorized':False,'requires_explicit_administrative_boundary_crosswalk':True,'first_candidate_wins_forbidden':True}
ENTRY_FIELDS=['osm_id','candidate_niscodes','geometry_sha256','road_record_sha256','point_count','bbox_m']
ROOT_FIELDS={'schema','production_base_sha','source_lock','source_artifacts','accounting','entry_fields','decision','authorization','frontier','parts'}
SOURCE_LOCK_FIELDS={'path','source_run_id','source_head_sha','source_provider','source_license','locked_duplicate_map_sha256'}
SOURCE_ARTIFACT_FIELDS={'municipality_id','niscode','osm_relation_id','artifact_id','artifact_digest','game_member','game_file_sha256','road_count','point_count'}
ACCOUNTING_FIELDS={'municipality_count','road_membership_count','unique_osm_road_count','duplicate_osm_id_count','duplicate_membership_excess','point_count','geometry_equivalent_duplicate_count','geometry_non_equivalent_duplicate_count','pair_duplicate_count','triple_duplicate_count','candidate_membership_sha256','materialized_duplicate_count','remaining_duplicate_count','materialized_entries_sha256'}
PART_FIELDS={'path','entry_count','first_osm_id','last_osm_id','file_sha256','entries_sha256'}
PART_ROOT_FIELDS={'schema','part_index','entry_fields','entries'}

def cb(v): return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def digest(v): return hashlib.sha256(cb(v)).hexdigest()
def sha(v,n=64,prefix=False):
    assert type(v) is str
    if prefix:
        assert v.startswith('sha256:'); v=v[7:]
    assert len(v)==n and all(c in HEX for c in v)

def validate_entries(entries, locked):
    assert type(entries) is list and entries
    ids=[e[0] for e in entries]; assert ids==sorted(ids) and len(ids)==len(set(ids))
    for e in entries:
        assert type(e) is list and len(e)==6
        osm,nises,gh,rh,pc,bb=e
        assert type(osm) is int and osm>0
        assert type(nises) is list and nises==sorted(nises) and len(nises) in {2,3} and len(set(nises))==len(nises)
        assert all(type(n) is str and n in locked for n in nises)
        sha(gh); sha(rh); assert type(pc) is int and pc>=2
        assert type(bb) is list and len(bb)==4 and all(type(v) in (int,float) and not isinstance(v,bool) and math.isfinite(v) for v in bb)
        assert bb[0]<=bb[2] and bb[1]<=bb[3]

def validate_source_artifact_row(r, x):
    assert type(r) is dict and set(r)==SOURCE_ARTIFACT_FIELDS
    assert (r['municipality_id'],r['osm_relation_id'],r['artifact_id'],r['artifact_digest'],r['game_file_sha256'],r['road_count'],r['point_count'])==(x['id'],x['osm_relation_id'],x['artifact_id'],x['artifact_digest'],x['game_file_sha256'],x['road_count'],x['point_count'])
    assert type(r['artifact_id']) is int and r['artifact_id']>0
    assert type(r['osm_relation_id']) is int and r['osm_relation_id']>0
    assert type(r['road_count']) is int and r['road_count']>0
    assert type(r['point_count']) is int and r['point_count']>0
    sha(r['artifact_digest'],prefix=True); sha(r['game_file_sha256'])
    assert type(r['game_member']) is str and r['game_member'].endswith('_road_source.game.json') and '/' not in r['game_member'] and '\\' not in r['game_member']

def load_and_validate():
    c=json.loads(CAT.read_text()); l=json.loads(LOCK.read_text())
    assert type(c) is dict and set(c)==ROOT_FIELDS and c['schema']=='grand-bruxelles-road-duplicate-candidate-crosswalk-batch-v1'
    assert c['production_base_sha']=='fed65c127f614f9435256cab69cf6fc0a56af867'; sha(c['production_base_sha'],40)
    sl=c['source_lock']; assert type(sl) is dict and set(sl)==SOURCE_LOCK_FIELDS
    assert sl['path']=='data/qa/brussels_missing_road_source_artifact_lock.json'
    assert sl['source_run_id']==l['source_run_id']==33286183671 and type(sl['source_run_id']) is int and sl['source_run_id']>0
    assert sl['source_head_sha']==l['source_head_sha']; sha(sl['source_head_sha'],40)
    assert sl['source_provider']==l['source_provider']=='OpenStreetMap contributors via Overpass API'
    assert sl['source_license']==l['source_license']=='ODbL-1.0'
    assert sl['locked_duplicate_map_sha256']==l['accounting']['duplicate_map_sha256']; sha(sl['locked_duplicate_map_sha256'])
    assert c['entry_fields']==ENTRY_FIELDS and c['decision']==DECISION
    assert set(c['authorization'])==CLOSED and all(c['authorization'][k] is False for k in CLOSED)
    locked={r['niscode']:r for r in l['municipalities']}; src=c['source_artifacts']
    assert type(src) is list and len(src)==len(locked)==16 and [r['niscode'] for r in src]==sorted(locked)
    for r in src:
        validate_source_artifact_row(r,locked[r['niscode']])
    ac=c['accounting']; assert type(ac) is dict and set(ac)==ACCOUNTING_FIELDS
    assert ac['municipality_count']==16 and ac['road_membership_count']==19707 and ac['unique_osm_road_count']==19113
    assert ac['duplicate_osm_id_count']==586 and ac['duplicate_membership_excess']==594 and ac['point_count']==118185
    assert ac['geometry_equivalent_duplicate_count']==586 and ac['geometry_non_equivalent_duplicate_count']==0
    assert ac['pair_duplicate_count']==578 and ac['triple_duplicate_count']==8
    assert ac['candidate_membership_sha256']=='990ddf3034d1cf36817dda1a0b5d20427b1e38e1664081736ac141840e1ebd0a'; sha(ac['candidate_membership_sha256'])
    assert ac['materialized_duplicate_count']==75 and ac['remaining_duplicate_count']==511
    assert all(type(ac[k]) is int and ac[k]>=0 for k in ACCOUNTING_FIELDS if k not in {'candidate_membership_sha256','materialized_entries_sha256'})
    sha(ac['materialized_entries_sha256'])
    parts=c['parts']; assert type(parts) is list and len(parts)==1; meta=parts[0]; assert type(meta) is dict and set(meta)==PART_FIELDS
    part_path=ROOT/meta['path']; raw=part_path.read_bytes(); assert hashlib.sha256(raw).hexdigest()==meta['file_sha256']; sha(meta['file_sha256']); sha(meta['entries_sha256'])
    part=json.loads(raw); assert type(part) is dict and set(part)==PART_ROOT_FIELDS
    assert part['schema']=='grand-bruxelles-road-duplicate-candidate-crosswalk-part-v1' and part['part_index']==0 and part['entry_fields']==ENTRY_FIELDS
    entries=part['entries']; validate_entries(entries,locked)
    assert len(entries)==meta['entry_count']==75 and entries[0][0]==meta['first_osm_id']==5229738 and entries[-1][0]==meta['last_osm_id']==23158768
    assert all(type(meta[k]) is int and not isinstance(meta[k],bool) for k in ('entry_count','first_osm_id','last_osm_id'))
    assert digest(entries)==meta['entries_sha256']==ac['materialized_entries_sha256']=='0bd8dd6ed7062f238c4bfc6d5886bdb1d5ec5507f8fa69b82f114db9145c12da'
    f=c['frontier']; assert f=={'selection':'ascending_osm_id','first_osm_id':5229738,'last_osm_id':23158768,'next_after_osm_id':23158768,'complete':False}
    return c,l,entries,locked

def test_contract(): load_and_validate()
def test_first_candidate_wins_injection_is_rejected():
    _,_,entries,locked=load_and_validate(); m=copy.deepcopy(entries); m[0]={'osm_id':m[0][0],'municipality':m[0][1][0]}
    with pytest.raises((AssertionError,KeyError,TypeError)): validate_entries(m,locked)
def test_candidate_reorder_is_rejected():
    _,_,entries,locked=load_and_validate(); m=copy.deepcopy(entries); m[0][1]=list(reversed(m[0][1]))
    with pytest.raises(AssertionError): validate_entries(m,locked)
def test_assignment_authorization_is_rejected():
    c,_,_,_=load_and_validate(); m=copy.deepcopy(c['decision']); m['municipality_assignment_authorized']=True; assert m!=DECISION
def test_runtime_authorization_is_rejected():
    c,_,_,_=load_and_validate(); m=copy.deepcopy(c['authorization']); m['runtime_mount_authorized']=True; assert not all(m[k] is False for k in CLOSED)
def test_frontier_cannot_claim_complete():
    c,_,_,_=load_and_validate(); m=copy.deepcopy(c['frontier']); m['complete']=True; assert m!=c['frontier']
def test_source_artifact_parallel_semantics_are_rejected():
    c,l,_,_=load_and_validate(); m=copy.deepcopy(c['source_artifacts'][0]); m['safe_spawn_ready']=True
    locked={r['niscode']:r for r in l['municipalities']}
    with pytest.raises(AssertionError): validate_source_artifact_row(m,locked[m['niscode']])
def test_source_artifact_bool_identity_is_rejected():
    c,l,_,_=load_and_validate(); m=copy.deepcopy(c['source_artifacts'][0]); m['artifact_id']=True
    locked={r['niscode']:r for r in l['municipalities']}
    with pytest.raises(AssertionError): validate_source_artifact_row(m,locked[m['niscode']])
