#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, json
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'data/qa/brussels_missing_road_source_artifact_lock.json'
CAT=ROOT/'data/qa/brussels_missing_road_duplicate_candidate_crosswalk.json'
HEX=set('0123456789abcdef')
CLOSED={'source_registration_authorized','road_cell_mapping_authorized','render_authorized','collision_authorized','runtime_mount_authorized','safe_spawn_authorized','jouable_authorized'}
ROOT_FIELDS={'schema','production_base_sha','source_lock','source_artifacts','accounting','entry_fields','decision','authorization','entries'}
SOURCE_LOCK_FIELDS={'path','source_run_id','source_head_sha','source_provider','source_license','locked_duplicate_map_sha256'}
SOURCE_FIELDS={'municipality_id','niscode','osm_relation_id','artifact_id','artifact_digest','game_member','game_file_sha256','road_count','point_count'}
ACCOUNTING_FIELDS={'municipality_count','road_membership_count','unique_osm_road_count','duplicate_osm_id_count','duplicate_membership_excess','point_count','geometry_equivalent_duplicate_count','geometry_non_equivalent_duplicate_count','pair_duplicate_count','triple_duplicate_count','candidate_membership_sha256','entries_sha256'}
DECISION={'municipality_assignment_authorized':False,'spatial_cell_assignment_authorized':False,'requires_explicit_administrative_boundary_crosswalk':True,'first_candidate_wins_forbidden':True}
ENTRY_FIELDS=['osm_id','candidate_niscodes','geometry_sha256','road_record_sha256','point_count','bbox_m']

def cb(v): return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def digest(v): return hashlib.sha256(cb(v)).hexdigest()
def fields(v,e,label):
    assert type(v) is dict and set(v)==e, f'{label}: field set drift'; return v
def sha(v,label,n=64,prefix=False):
    assert type(v) is str, f'{label}: expected string'
    if prefix:
        assert v.startswith('sha256:'), f'{label}: invalid prefix'; v=v[7:]
    assert len(v)==n and all(c in HEX for c in v), f'{label}: invalid digest'

def validate(c,l):
    fields(c,ROOT_FIELDS,'catalog'); assert c['schema']=='grand-bruxelles-road-duplicate-candidate-crosswalk-v1'; sha(c['production_base_sha'],'production_base_sha',40)
    sl=fields(c['source_lock'],SOURCE_LOCK_FIELDS,'source_lock')
    assert sl['path']=='data/qa/brussels_missing_road_source_artifact_lock.json'; assert sl['source_run_id']==l['source_run_id']==33286183671
    assert sl['source_head_sha']==l['source_head_sha']; sha(sl['source_head_sha'],'source_head_sha',40)
    assert sl['source_provider']==l['source_provider']=='OpenStreetMap contributors via Overpass API'; assert sl['source_license']==l['source_license']=='ODbL-1.0'
    assert sl['locked_duplicate_map_sha256']==l['accounting']['duplicate_map_sha256']; sha(sl['locked_duplicate_map_sha256'],'locked_duplicate_map_sha256')
    assert c['entry_fields']==ENTRY_FIELDS; assert fields(c['decision'],set(DECISION),'decision')==DECISION
    a=fields(c['authorization'],CLOSED,'authorization'); assert all(a[k] is False for k in CLOSED)
    locked={r['niscode']:r for r in l['municipalities']}; src=c['source_artifacts']; assert type(src) is list and len(src)==len(locked)==16; assert [r['niscode'] for r in src]==sorted(locked)
    for r in src:
        fields(r,SOURCE_FIELDS,'source'); x=locked[r['niscode']]
        assert (r['municipality_id'],r['osm_relation_id'],r['artifact_id'],r['artifact_digest'],r['game_file_sha256'],r['road_count'],r['point_count'])==(x['id'],x['osm_relation_id'],x['artifact_id'],x['artifact_digest'],x['game_file_sha256'],x['road_count'],x['point_count'])
        sha(r['artifact_digest'],f"{r['niscode']} artifact",prefix=True); sha(r['game_file_sha256'],f"{r['niscode']} game")
        assert r['game_member'].endswith('_road_source.game.json') and '/' not in r['game_member'] and '\\' not in r['game_member']
    entries=c['entries']; assert type(entries) is list and len(entries)==586; assert all(type(e) is list and len(e)==6 for e in entries); assert [e[0] for e in entries]==sorted(e[0] for e in entries); assert len({e[0] for e in entries})==586
    mmap={}; pairs=triples=0
    for e in entries:
        assert type(e) is list and len(e)==6; osm,nises,gh,rh,pc,bb=e
        assert type(osm) is int and osm>0; assert type(nises) is list and nises==sorted(nises) and len(set(nises))==len(nises) and len(nises) in {2,3}; assert all(type(n) is str and n in locked for n in nises)
        pairs+=len(nises)==2; triples+=len(nises)==3; sha(gh,f'{osm} geometry'); sha(rh,f'{osm} road'); assert type(pc) is int and pc>=2
        assert type(bb) is list and len(bb)==4 and all(type(v) in (int,float) and not isinstance(v,bool) for v in bb) and bb[0]<=bb[2] and bb[1]<=bb[3]
        mmap[str(osm)]=nises
    ac=fields(c['accounting'],ACCOUNTING_FIELDS,'accounting')
    assert ac['municipality_count']==l['accounting']['municipality_count']==16; assert ac['road_membership_count']==l['accounting']['road_membership_count']==19707; assert ac['unique_osm_road_count']==l['accounting']['unique_osm_road_count']==19113
    assert ac['duplicate_osm_id_count']==l['accounting']['cross_municipality_duplicate_osm_id_count']==586; assert ac['duplicate_membership_excess']==l['accounting']['duplicate_membership_excess']==594; assert ac['point_count']==l['accounting']['point_count']==118185
    assert ac['geometry_equivalent_duplicate_count']==586 and ac['geometry_non_equivalent_duplicate_count']==0 and ac['pair_duplicate_count']==pairs==578 and ac['triple_duplicate_count']==triples==8
    assert sum(len(e[1])-1 for e in entries)==594; assert ac['candidate_membership_sha256']==digest(mmap); assert ac['entries_sha256']==digest(entries); sha(ac['candidate_membership_sha256'],'candidate map'); sha(ac['entries_sha256'],'entries')

def load(): return json.loads(CAT.read_text()),json.loads(LOCK.read_text())
def test_contract(): c,l=load(); validate(c,l)
def test_first_candidate_wins_field_injection_is_rejected():
    c,l=load(); m=copy.deepcopy(c); m['entries'][0]={'osm_id':m['entries'][0][0],'municipality':m['entries'][0][1][0]}
    with pytest.raises(AssertionError): validate(m,l)
def test_candidate_reorder_is_rejected():
    c,l=load(); m=copy.deepcopy(c); m['entries'][0][1]=list(reversed(m['entries'][0][1]))
    with pytest.raises(AssertionError): validate(m,l)
def test_assignment_authorization_is_rejected():
    c,l=load(); m=copy.deepcopy(c); m['decision']['municipality_assignment_authorized']=True
    with pytest.raises(AssertionError): validate(m,l)
def test_runtime_authorization_is_rejected():
    c,l=load(); m=copy.deepcopy(c); m['authorization']['runtime_mount_authorized']=True
    with pytest.raises(AssertionError): validate(m,l)
