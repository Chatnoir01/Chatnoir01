#!/usr/bin/env python3
"""Fail-closed validator for Bourse 8512036 capsule contact-axis ground continuity."""
from __future__ import annotations
import argparse, json, math
from pathlib import Path
from typing import Any

EXPECTED_SCHEMA="grand-bruxelles-bourse-8512036-ground-continuity-v6"
EXPECTED_ROAD_ID=8512036
EXPECTED_REQUEST="road-8512036"
EXPECTED_LOOKUP_MODE="deterministic_runtime_index"
EXPECTED_SOURCE_PATH="res://data/osm/vertical_slice_01.game.json"
EXPECTED_STATION_COUNT=7
EXPECTED_PROBE_COUNT=7
EXPECTED_PROBE_MODEL="capsule_contact_axis_centerline_v1"
EXPECTED_COLLISION_SHAPE_TYPE="CapsuleShape3D"
EXPECTED_COLLISION_MASK=524288
EXPECTED_OWNER_META="grand_bruxelles_owner"
EXPECTED_ROAD_IDS_META="road_support_osm_ids"
NORMAL_EPSILON=1e-4

def _reject_constant(value:str)->None: raise ValueError(f"non-standard JSON numeric constant rejected: {value}")
def _reject_duplicate_pairs(pairs:list[tuple[str,Any]])->dict[str,Any]:
    out={}
    for k,v in pairs:
        if k in out: raise ValueError(f"duplicate JSON key rejected: {k}")
        out[k]=v
    return out

def load_json_strict(path:Path)->dict[str,Any]:
    value=json.loads(path.read_text(encoding="utf-8"),parse_constant=_reject_constant,object_pairs_hook=_reject_duplicate_pairs)
    if type(value) is not dict: raise ValueError("receipt root must be object")
    return value

def num(v:Any,label:str)->float:
    if type(v) not in (int,float): raise ValueError(f"{label} must be canonical JSON number")
    n=float(v)
    if not math.isfinite(n): raise ValueError(f"{label} must be finite")
    return n

def integer(v:Any,label:str,positive=False)->int:
    if type(v) is not int: raise ValueError(f"{label} must be canonical JSON integer")
    if positive and v<=0: raise ValueError(f"{label} must be positive")
    return v

def arr(v:Any,n:int,label:str)->list[float]:
    if type(v) is not list or len(v)!=n: raise ValueError(f"{label} must contain exactly {n} values")
    return [num(x,f"{label}[{i}]") for i,x in enumerate(v)]

def ids(v:Any,label:str)->list[int]:
    if type(v) is not list or not v: raise ValueError(f"{label} must be non-empty")
    out=[]; seen=set()
    for i,x in enumerate(v):
        x=integer(x,f"{label}[{i}]",True)
        if x in seen: raise ValueError(f"{label} duplicate id")
        seen.add(x); out.append(x)
    return out

def validate(d:dict[str,Any],source_sha:str,runtime_sha:str,owner_id:str,base=None,head=None,sealed=False)->None:
    if d.get("schema")!=EXPECTED_SCHEMA: raise ValueError("unexpected schema")
    if integer(d.get("road_osm_id"),"road_osm_id",True)!=EXPECTED_ROAD_ID: raise ValueError("road identity mismatch")
    if d.get("request")!=EXPECTED_REQUEST or d.get("lookup_mode")!=EXPECTED_LOOKUP_MODE: raise ValueError("request/lookup mismatch")
    if d.get("source_path")!=EXPECTED_SOURCE_PATH or d.get("source_sha256")!=source_sha: raise ValueError("source identity mismatch")
    if integer(d.get("station_count"),"station_count",True)!=EXPECTED_STATION_COUNT or integer(d.get("probe_count"),"probe_count",True)!=EXPECTED_PROBE_COUNT: raise ValueError("probe count mismatch")
    if d.get("probe_model")!=EXPECTED_PROBE_MODEL: raise ValueError("unexpected probe model")
    if d.get("player_collision_shape_type")!=EXPECTED_COLLISION_SHAPE_TYPE or num(d.get("player_capsule_radius_m"),"player_capsule_radius_m")<=0: raise ValueError("capsule contract mismatch")
    if integer(d.get("surface_collision_mask"),"surface_collision_mask",True)!=EXPECTED_COLLISION_MASK: raise ValueError("collision mask mismatch")
    if d.get("collision_owner_meta")!=EXPECTED_OWNER_META or d.get("collision_owner_id")!=owner_id or d.get("collision_road_ids_meta")!=EXPECTED_ROAD_IDS_META: raise ValueError("owner contract mismatch")
    for flag in ("all_contact_axis_probes_collision_backed","all_contact_axis_probes_canonical_collision_owner","all_contact_axis_probes_exact_requested_osm_id_owned","all_contact_axis_probes_walkable_by_player_floor_max_angle","source_sightline_clear"):
        if d.get(flag) is not True: raise ValueError(f"{flag} must be true")
    if d.get("lateral_edge_ray_diagnostic_is_release_gate") is not False: raise ValueError("edge-ray diagnostic must remain non-release")
    angle=num(d.get("player_floor_max_angle_rad"),"player_floor_max_angle_rad"); min_y=num(d.get("minimum_walkable_normal_y"),"minimum_walkable_normal_y")
    if not 0<angle<math.pi/2 or abs(min_y-math.cos(angle))>1e-6: raise ValueError("floor angle contract mismatch")
    spawn=arr(d.get("spawn_xz"),2,"spawn_xz"); target=arr(d.get("target_xz"),2,"target_xz")
    dx,dz=target[0]-spawn[0],target[1]-spawn[1]; length=math.hypot(dx,dz)
    if length<10: raise ValueError("corridor proof length below 10m")
    samples=d.get("samples")
    if type(samples) is not list or len(samples)!=EXPECTED_PROBE_COUNT: raise ValueError("samples must contain 7 contact-axis probes")
    seen=set()
    for i,row in enumerate(samples):
        if type(row) is not dict: raise ValueError("sample must be object")
        station=integer(row.get("station_index"),f"samples[{i}].station_index")
        if station in seen or not 0<=station<EXPECTED_STATION_COUNT: raise ValueError("station index invalid/duplicate")
        seen.add(station); t=station/(EXPECTED_STATION_COUNT-1)
        if abs(num(row.get("t"),"t")-t)>1e-12: raise ValueError("t mismatch")
        xz=arr(row.get("xz"),2,"xz"); ex=(spawn[0]+dx*t,spawn[1]+dz*t)
        if abs(xz[0]-ex[0])>1e-4 or abs(xz[1]-ex[1])>1e-4: raise ValueError("contact-axis point mismatch")
        num(row.get("ground_y"),"ground_y"); normal=arr(row.get("normal"),3,"normal")
        if abs(math.sqrt(sum(x*x for x in normal))-1)>1e-4: raise ValueError("normal not unit")
        ny=num(row.get("normal_y"),"normal_y")
        if abs(ny-normal[1])>1e-6 or ny+NORMAL_EPSILON<min_y or row.get("walkable_by_player_floor_max_angle") is not True: raise ValueError("non-walkable normal")
        if row.get("collider_owner_id")!=owner_id: raise ValueError("owner mismatch")
        owned=ids(row.get("collider_road_support_osm_ids"),"road ids")
        if EXPECTED_ROAD_ID not in owned or row.get("requested_osm_id_owned") is not True: raise ValueError("requested road ownership missing")
    if seen!=set(range(EXPECTED_STATION_COUNT)): raise ValueError("station coverage incomplete")
    for key in ("source_geometry_changed","collision_geometry_changed","camera_changed","resolver_thresholds_lowered","destination_advertisable","visual_acceptance","jouable_authorized"):
        if d.get(key) is not False: raise ValueError(f"{key} must be false")
    if sealed:
        if d.get("base_sha")!=base or d.get("head_sha")!=head or d.get("runtime_index_sha256")!=runtime_sha: raise ValueError("sealed identity mismatch")

def self_test()->None:
    for bad in ("0.5",True,float("nan")):
        try: num(bad,"regression")
        except ValueError: pass
        else: raise AssertionError("bad number accepted")
    for bad in (["8512036"],[True],[8512036,8512036],[0],[]):
        try: ids(bad,"regression")
        except ValueError: pass
        else: raise AssertionError("bad ids accepted")

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument("receipt",type=Path); p.add_argument("base_sha"); p.add_argument("head_sha"); p.add_argument("source_sha"); p.add_argument("runtime_index_sha"); p.add_argument("owner_id"); a=p.parse_args()
    self_test(); d=load_json_strict(a.receipt); validate(d,a.source_sha,a.runtime_index_sha,a.owner_id)
    d["base_sha"]=a.base_sha; d["head_sha"]=a.head_sha; d["runtime_index_sha256"]=a.runtime_index_sha
    a.receipt.write_text(json.dumps(d,indent=2,sort_keys=True,allow_nan=False)+"\n",encoding="utf-8")
    validate(load_json_strict(a.receipt),a.source_sha,a.runtime_index_sha,a.owner_id,a.base_sha,a.head_sha,True)
    print("BOURSE_8512036_GROUND_CONTINUITY_RECEIPT_GREEN probe_model=capsule_contact_axis_centerline_v1 probes=7 strict_json=true exact_requested_osm_ownership=true")
    return 0
if __name__=="__main__": raise SystemExit(main())
