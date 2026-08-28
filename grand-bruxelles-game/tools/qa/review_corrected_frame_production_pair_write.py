#!/usr/bin/env python3
import argparse, hashlib, json
from pathlib import Path

CROSSWALK_TOP_FALSE = (
    "collision_authorized", "jouable_promotion_authorized",
    "rendered_geometry_authorized", "road_cell_mapping_authorized",
)
CROSSWALK_ROW_FALSE = CROSSWALK_TOP_FALSE + (
    "runtime_mount_authorized", "safe_spawn_authorized",
)
READINESS_AUTH_FALSE = (
    "collision_authorized", "jouable_authorized", "render_authorized",
    "road_cell_mapping_authorized", "runtime_directory_scan_authorized",
    "runtime_mount_authorized", "safe_spawn_authorized",
)
READINESS_ROW_FALSE = (
    "collision_authorized", "jouable_authorized", "render_authorized",
    "runtime_mount_authorized", "safe_spawn_authorized",
)
CONTRACT_FALSE = (
    "write_production_files_authorized", "production_frame_update_authorized",
    "road_cell_mapping_authorized", "runtime_probe_authorized", "runtime_mount_authorized",
    "render_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_authorized",
)

def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def require_false(obj, keys, label):
    missing=[k for k in keys if k not in obj]
    if missing: raise AssertionError(f"{label} missing fail-closed rails: {missing}")
    opened=[k for k in keys if obj[k] is not False]
    if opened: raise AssertionError(f"{label} opened authorization: {opened}")

def crosswalk_table(doc, label):
    require_false(doc, CROSSWALK_TOP_FALSE, label)
    rows=doc.get("rows")
    if not isinstance(rows,list): raise AssertionError(f"{label} canonical rows missing")
    out={}
    for row in rows:
        require_false(row, CROSSWALK_ROW_FALSE, f"{label} road {row.get('road_osm_id')}")
        rid=int(row["road_osm_id"])
        if rid in out: raise AssertionError(f"duplicate {label} road mapping {rid}")
        out[rid]=row["cell_id"]
    declared=doc.get("mapped_road_count")
    if declared is not None and int(declared)!=len(out):
        raise AssertionError(f"{label} mapped_road_count drift: {declared} != {len(out)}")
    return out

def readiness_table(doc, label, source):
    auth=doc.get("authorization")
    if not isinstance(auth,dict): raise AssertionError(f"{label} authorization object missing")
    require_false(auth, READINESS_AUTH_FALSE, f"{label} authorization")
    rows=doc.get("destinations")
    if not isinstance(rows,list): raise AssertionError(f"{label} canonical destinations missing")
    out={}
    for row in rows:
        require_false(row, READINESS_ROW_FALSE, f"{label} road {row.get('road_osm_id')}")
        rid=int(row["road_osm_id"])
        if rid in out: raise AssertionError(f"duplicate {label} road {rid}")
        if row.get("destination_id") != f"road-{rid}":
            raise AssertionError(f"{label} destination identity mismatch for {rid}")
        if row.get("source_license") != source["license"]:
            raise AssertionError(f"{label} source license drift for {rid}")
        if row.get("source_sha256") != source["road_source_sha256"]:
            raise AssertionError(f"{label} source hash drift for {rid}")
        out[rid]=row["cell_id"]
    declared=doc.get("destination_count")
    if declared is not None and int(declared)!=len(out):
        raise AssertionError(f"{label} destination_count drift: {declared} != {len(out)}")
    return out

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--contract", required=True)
    p.add_argument("--production-crosswalk", required=True)
    p.add_argument("--production-readiness", required=True)
    p.add_argument("--staged-crosswalk", required=True)
    p.add_argument("--staged-readiness", required=True)
    p.add_argument("--output", required=True)
    a=p.parse_args()
    c=load(a.contract); pc=load(a.production_crosswalk); pr=load(a.production_readiness)
    sc=load(a.staged_crosswalk); sr=load(a.staged_readiness)
    if c.get("status") not in {"MEASUREMENT_PENDING","LOCKED_ATOMIC_WRITE_APPLICABILITY_EVIDENCE_ONLY"}:
        raise AssertionError(f"unsupported review contract status: {c.get('status')}")
    source=c["source"]
    assert source["license"] == "ODbL-1.0"
    assert source["crs"] == "EPSG:31370"
    assert source["road_source_sha256"] == "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
    assert sha(a.staged_crosswalk) == c["staged_pair"]["crosswalk_sha256"]
    assert sha(a.staged_readiness) == c["staged_pair"]["readiness_sha256"]
    require_false(c["authorization"], CONTRACT_FALSE, "review contract")

    pm=crosswalk_table(pc,"production crosswalk")
    pd=readiness_table(pr,"production readiness",source)
    sm=crosswalk_table(sc,"staged crosswalk")
    sd=readiness_table(sr,"staged readiness",source)
    assert pm == pd, "production crosswalk/readiness mismatch"
    assert sm == sd, "staged crosswalk/readiness mismatch"
    assert len(pm)==c["production_expected"]["mapping_count"]==56
    assert len(pd)==c["production_expected"]["destination_count"]==56
    assert len(sm)==c["staged_pair"]["mapping_count"]==96
    assert len(sd)==c["staged_pair"]["destination_count"]==96
    assert len(set(sm.values()))==c["staged_pair"]["mapped_cell_count"]==4
    if int(sr.get("mapped_cell_count",-1)) != 4:
        raise AssertionError("staged readiness mapped_cell_count must be 4")

    expected_holds={int(x) for x in c["multi_cell_hold_ids"]}
    staged_holds={int(x) for x in sc.get("excluded_multicell_road_ids",[])}
    assert staged_holds == expected_holds, (staged_holds, expected_holds)
    assert not expected_holds.intersection(sm), "HOLD road leaked into staged unique mappings"
    assert not expected_holds.intersection(sd), "HOLD road leaked into staged readiness"

    shared=set(pm)&set(sm)
    retained=sorted(r for r in shared if pm[r]==sm[r])
    changed=sorted(r for r in shared if pm[r]!=sm[r])
    new=sorted(set(sm)-set(pm)); removed=sorted(set(pm)-set(sm))
    exp=c["migration_expected"]
    assert len(retained)==exp["retained_same_cell"]==0
    assert len(changed)==exp["changed_cell"]==45
    assert len(new)==exp["new"]==51
    assert len(removed)==exp["removed"]==11

    review={
      "schema":"grand-bruxelles-corrected-frame-production-pair-write-review-v1",
      "status":"ATOMIC_WRITE_APPLICABILITY_PROVEN_EVIDENCE_ONLY",
      "production_base_sha":c["production_base_sha"],
      "source":source,
      "production":{"mapping_count":len(pm),"destination_count":len(pd)},
      "candidate":{"mapping_count":len(sm),"destination_count":len(sd),"mapped_cell_count":len(set(sm.values()))},
      "migration":{"retained_same_cell":len(retained),"changed_cell":len(changed),"new":len(new),"removed":len(removed),"multi_cell_hold_count":len(expected_holds)},
      "multi_cell_hold_ids":sorted(expected_holds),
      "authorization":c["authorization"],
    }
    semantic={k:v for k,v in review.items() if k!="production_base_sha"}
    review["semantic_sha256"]=hashlib.sha256(json.dumps(semantic,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
    locked=c.get("locked_evidence")
    if c.get("status")=="LOCKED_ATOMIC_WRITE_APPLICABILITY_EVIDENCE_ONLY":
        if not isinstance(locked,dict): raise AssertionError("locked evidence missing")
        if review["semantic_sha256"] != locked.get("review_semantic_sha256"):
            raise AssertionError("locked review semantic drift")
    Path(a.output).write_text(json.dumps(review,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8")
    print("CORRECTED_FRAME_PRODUCTION_PAIR_WRITE_REVIEW_OK", review["semantic_sha256"])
if __name__=="__main__": main()
