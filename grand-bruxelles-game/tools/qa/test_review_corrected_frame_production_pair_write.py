#!/usr/bin/env python3
import hashlib, json, subprocess, tempfile
from pathlib import Path

SCRIPT=Path(__file__).with_name("review_corrected_frame_production_pair_write.py")
SOURCE_SHA="899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
CW_TOP={"collision_authorized":False,"jouable_promotion_authorized":False,"rendered_geometry_authorized":False,"road_cell_mapping_authorized":False}
CW_ROW={**CW_TOP,"runtime_mount_authorized":False,"safe_spawn_authorized":False}
RD_AUTH={"collision_authorized":False,"jouable_authorized":False,"render_authorized":False,"road_cell_mapping_authorized":False,"runtime_directory_scan_authorized":False,"runtime_mount_authorized":False,"safe_spawn_authorized":False}
RD_ROW={"collision_authorized":False,"jouable_authorized":False,"render_authorized":False,"runtime_mount_authorized":False,"safe_spawn_authorized":False}

def write(p,o): p.write_text(json.dumps(o,sort_keys=True)+"\n")
def rd_row(rid,cell):
    return {"road_osm_id":rid,"cell_id":cell,"destination_id":f"road-{rid}","source_license":"ODbL-1.0","source_sha256":SOURCE_SHA,**RD_ROW}
def cw_row(rid,cell): return {"road_osm_id":rid,"cell_id":cell,**CW_ROW}

def base_docs():
    prod=[cw_row(i,"A") for i in range(56)]
    staged=[]
    for i in range(45): staged.append(cw_row(i,"B"))
    for i in range(56,107): staged.append(cw_row(i,["A","B","C","D"][i%4]))
    pc={**CW_TOP,"mapped_road_count":56,"rows":prod}
    pr={"authorization":dict(RD_AUTH),"destination_count":56,"destinations":[rd_row(r["road_osm_id"],r["cell_id"]) for r in prod]}
    sc={**CW_TOP,"mapped_road_count":96,"mapped_cell_count":4,"excluded_multicell_road_ids":[9001,9002],"rows":staged}
    sr={"authorization":dict(RD_AUTH),"destination_count":96,"mapped_cell_count":4,"destinations":[rd_row(r["road_osm_id"],r["cell_id"]) for r in staged]}
    return pc,pr,sc,sr

def make_contract(d,sc,sr,status="MEASUREMENT_PENDING",locked_semantic=None,base="x",evidence_base="x"):
    c={
      "status":status,
      "source":{"license":"ODbL-1.0","crs":"EPSG:31370","road_source_sha256":SOURCE_SHA},
      "production_base_sha":base,
      "staged_pair":{"crosswalk_sha256":hashlib.sha256((d/"sc.json").read_bytes()).hexdigest(),"readiness_sha256":hashlib.sha256((d/"sr.json").read_bytes()).hexdigest(),"mapping_count":96,"destination_count":96,"mapped_cell_count":4},
      "production_expected":{"mapping_count":56,"destination_count":56},
      "migration_expected":{"retained_same_cell":0,"changed_cell":45,"new":51,"removed":11},
      "multi_cell_hold_ids":[9001,9002],
      "authorization":{"write_production_files_authorized":False,"production_frame_update_authorized":False,"road_cell_mapping_authorized":False,"runtime_probe_authorized":False,"runtime_mount_authorized":False,"render_authorized":False,"collision_authorized":False,"safe_spawn_authorized":False,"jouable_authorized":False}}
    if status=="LOCKED_ATOMIC_WRITE_APPLICABILITY_EVIDENCE_ONLY":
        c["locked_evidence"]={
            "production_base_sha":evidence_base,
            "byte_identity_policy":"exact_on_evidence_base_semantic_on_descendant_live_main",
            "review_semantic_sha256":locked_semantic,
        }
    return c

def run_case(mutator=None, expect=0):
    with tempfile.TemporaryDirectory() as td:
        d=Path(td); pc,pr,sc,sr=base_docs()
        if mutator: mutator(pc,pr,sc,sr)
        for name,obj in (("pc",pc),("pr",pr),("sc",sc),("sr",sr)): write(d/f"{name}.json",obj)
        contract=make_contract(d,sc,sr)
        write(d/"c.json",contract)
        r=subprocess.run(["python3",str(SCRIPT),"--contract",str(d/"c.json"),"--production-crosswalk",str(d/"pc.json"),"--production-readiness",str(d/"pr.json"),"--staged-crosswalk",str(d/"sc.json"),"--staged-readiness",str(d/"sr.json"),"--output",str(d/"o.json")],capture_output=True,text=True)
        assert (r.returncode==0)==(expect==0), (r.stdout,r.stderr)

def run_locked_evidence_cases():
    with tempfile.TemporaryDirectory() as td:
        d=Path(td); pc,pr,sc,sr=base_docs()
        for name,obj in (("pc",pc),("pr",pr),("sc",sc),("sr",sr)): write(d/f"{name}.json",obj)
        pending=make_contract(d,sc,sr,base="base-a")
        write(d/"c.json",pending)
        cmd=["python3",str(SCRIPT),"--contract",str(d/"c.json"),"--production-crosswalk",str(d/"pc.json"),"--production-readiness",str(d/"pr.json"),"--staged-crosswalk",str(d/"sc.json"),"--staged-readiness",str(d/"sr.json"),"--output",str(d/"o.json")]
        r=subprocess.run(cmd,capture_output=True,text=True); assert r.returncode==0,(r.stdout,r.stderr)
        first_raw=(d/"o.json").read_bytes(); first=json.loads(first_raw)
        sem=first["semantic_sha256"]

        locked=make_contract(d,sc,sr,"LOCKED_ATOMIC_WRITE_APPLICABILITY_EVIDENCE_ONLY",sem,base="base-a",evidence_base="base-a")
        write(d/"c.json",locked)
        r=subprocess.run(cmd,capture_output=True,text=True); assert r.returncode==0,(r.stdout,r.stderr)
        historical_raw=(d/"o.json").read_bytes(); historical=json.loads(historical_raw)
        assert historical["semantic_sha256"]==sem
        assert historical["production_base_sha"]=="base-a"

        # A clean descendant-main rebuild changes only the forensic byte receipt.
        # Semantic identity must remain exact because production_base_sha is intentionally excluded.
        rebuilt=make_contract(d,sc,sr,"LOCKED_ATOMIC_WRITE_APPLICABILITY_EVIDENCE_ONLY",sem,base="base-b",evidence_base="base-a")
        write(d/"c.json",rebuilt)
        r=subprocess.run(cmd,capture_output=True,text=True); assert r.returncode==0,(r.stdout,r.stderr)
        rebuilt_raw=(d/"o.json").read_bytes(); rebuilt_doc=json.loads(rebuilt_raw)
        assert rebuilt_doc["semantic_sha256"]==sem
        assert rebuilt_doc["production_base_sha"]=="base-b"
        assert rebuilt_raw!=historical_raw, "base-only rebuild must change forensic receipt bytes"
        assert hashlib.sha256(rebuilt_raw).hexdigest()!=hashlib.sha256(historical_raw).hexdigest()

        rebuilt["locked_evidence"]["review_semantic_sha256"]="0"*64
        write(d/"c.json",rebuilt)
        r=subprocess.run(cmd,capture_output=True,text=True); assert r.returncode!=0,"semantic lock drift must fail closed"

def main():
    run_case()
    run_case(lambda pc,pr,sc,sr: pc.pop("road_cell_mapping_authorized"),1)
    run_case(lambda pc,pr,sc,sr: pr["authorization"].pop("runtime_mount_authorized"),1)
    run_case(lambda pc,pr,sc,sr: sr["destinations"][0].__setitem__("destination_id","road-999999"),1)
    run_case(lambda pc,pr,sc,sr: sr["destinations"][0].__setitem__("source_sha256","0"*64),1)
    run_case(lambda pc,pr,sc,sr: sc.__setitem__("excluded_multicell_road_ids",[9001]),1)
    run_case(lambda pc,pr,sc,sr: sc["rows"].__setitem__(0,{**sc["rows"][0],"road_cell_mapping_authorized":True}),1)
    run_case(lambda pc,pr,sc,sr: sr.__setitem__("mapped_cell_count",3),1)
    run_locked_evidence_cases()
    print("corrected-frame production pair write review regressions: OK")
if __name__=="__main__": main()
