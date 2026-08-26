#!/usr/bin/env python3
"""Fail-closed Anneessens canonical-registration preflight from persisted evidence only."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

CELL_ID = "bxl-e147500-n169500-s500"
BBOX = [147500.0, 169500.0, 148000.0, 170000.0]
SOURCE_REL = Path("data/urbis/remaining_brussels/cells") / CELL_ID
SOURCE_LOCK = Path("data/provenance/anneessens_urbis_source_cell.measurement.json")
SOURCE_CONTRACT = Path("data/qa/anneessens_urbis_source_cell.contract.json")
MUNICIPAL_LOCK = Path("data/provenance/anneessens_source_cell_municipality.measurement.json")
REGISTERED_INDEX = Path("data/provenance/brussels_registered_cell_manifest_index.json")
EXPECTED_SOURCE_SEMANTIC = "496e1049db535dbf3db2192066f41f60e9297e7b7931d9a8a427d6ffa378f8b0"
EXPECTED_MUNICIPAL_SEMANTIC = "4148e300ea5a81d60b5f16f0eab1186a3d646308cb7a4a4a1c5036b21e2bba8f"
EXPECTED_INDEX_SEMANTIC = "2b34adfdda1adb2eb34aca7c89ca90e73a11633394b6fe3c3e30b2318cc00fac"
EXPECTED_COUNTS = {"buildings":362,"street_axes":104,"street_surfaces":283,"train_network":361,"tram_network":361}
EXPECTED_MUNICIPALITIES = [
    ("21013","https://databrussels.be/id/municipality/5000083",161393.61662905017,0.6455744665162007,"Saint-Gilles","Sint-Gillis"),
    ("21001","https://databrussels.be/id/municipality/5000071",87901.38362680243,0.3516055345072097,"Anderlecht","Anderlecht"),
    ("21004","https://databrussels.be/id/municipality/5000074",704.9997441473968,0.002819998976589587,"Bruxelles","Brussel"),
]
CLOSED_INDEX_RAILS=("road_crosswalk_authorized","runtime_directory_scan_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized")

def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build_review(game_root: Path, production_base_sha: str) -> dict:
    source_dir=game_root/SOURCE_REL
    source_lock=load(game_root/SOURCE_LOCK)
    source_contract=load(game_root/SOURCE_CONTRACT)
    municipal=load(game_root/MUNICIPAL_LOCK)
    index=load(game_root/REGISTERED_INDEX)
    manifest_path=source_dir/"manifest.json"
    maturity_path=source_dir/"maturity.json"
    manifest=load(manifest_path)
    maturity=load(maturity_path)

    if source_contract["source"]["authority"]!="Paradigm / Brussels-Capital Region" or source_contract["source"]["license"]!="CC0-1.0":
        raise RuntimeError("Anneessens source authority/license drift")
    if source_lock["cell_id"]!=CELL_ID or source_lock["crs"]!="EPSG:31370" or source_lock["bbox"]!=BBOX:
        raise RuntimeError("Anneessens source identity/CRS/bbox drift")
    if source_lock["source_semantic_sha256"]!=EXPECTED_SOURCE_SEMANTIC:
        raise RuntimeError("Anneessens source semantic drift")
    if source_lock["manifest_sha256"]!=sha256(manifest_path) or source_lock["maturity_sha256"]!=sha256(maturity_path):
        raise RuntimeError("Anneessens persisted manifest/maturity byte drift")
    if manifest["source_digest"]!=source_lock["manifest_source_digest"] or manifest["promotion"]!="source_only_no_runtime_mutation":
        raise RuntimeError("Anneessens source manifest provenance/promotion drift")
    for layer,count in EXPECTED_COUNTS.items():
        row=source_lock["layers"][layer]
        if int(row["features"])!=count or int(manifest["layers"][layer]["features"])!=count:
            raise RuntimeError(f"Anneessens layer accounting drift: {layer}")
        raw=source_dir/manifest["layers"][layer]["file"]
        if not raw.is_file() or sha256(raw)!=row["raw_forensic_sha256"] or raw.stat().st_size!=int(row["raw_bytes"]):
            raise RuntimeError(f"Anneessens persisted raw bytes drift: {layer}")
    b=source_lock["layers"]["buildings"]
    if int(b["ownership_filtered"])!=52 or int(b["invalid_ownership_features"])!=0:
        raise RuntimeError("Anneessens building ownership accounting drift")
    for key in ("registration_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized"):
        if source_lock.get(key) is not False:
            raise RuntimeError(f"Anneessens source rail unexpectedly open: {key}")
    if maturity["maturity"]["state"]!="data_ready":
        raise RuntimeError("Anneessens source cell is not data_ready")
    for key in ("runtime_geometry","collisions","streaming","terrain","heights","photo_match","performance"):
        if maturity["maturity"]["gates"].get(key) is not False:
            raise RuntimeError(f"Anneessens maturity gate unexpectedly open: {key}")

    if municipal["status"]!="HOLD_MUNICIPALITY_BOUNDARY_CELL" or municipal["semantic_sha256"]!=EXPECTED_MUNICIPAL_SEMANTIC:
        raise RuntimeError("Anneessens municipality boundary proof drift")
    cov=municipal["municipality_coverage"]
    if cov["municipality_id"] is not None or cov["municipality_niscode"] is not None or abs(float(cov["intersection_coverage_sum"])-1.0)>1e-12:
        raise RuntimeError("Anneessens boundary cell collapsed or incomplete")
    actual=cov["intersections"]
    if len(actual)!=3:
        raise RuntimeError("Anneessens must retain all three municipality intersections")
    for row,expected in zip(actual,EXPECTED_MUNICIPALITIES):
        nis,mid,area,ratio,name_fr,name_nl=expected
        if str(row["properties"]["NISCODE"])!=nis or row["municipality_id"]!=mid:
            raise RuntimeError("Anneessens municipality identity/order drift")
        if row["properties"]["NAMEFRE"]!=name_fr or row["properties"]["NAMEDUT"]!=name_nl:
            raise RuntimeError("Anneessens municipality names drift")
        if abs(float(row["intersection_area_m2"])-area)>1e-6 or abs(float(row["coverage_ratio"])-ratio)>1e-12:
            raise RuntimeError("Anneessens municipality geometry/accounting drift")
    for key in ("source_registration_authorized","canonical_registration_authorized","municipality_assignment_authorized","road_cell_mapping_authorized","runtime_directory_scan_authorized","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","jouable_promotion_authorized"):
        if municipal.get(key) is not False:
            raise RuntimeError(f"Anneessens municipality rail unexpectedly open: {key}")

    for key in CLOSED_INDEX_RAILS:
        if index.get(key) is not False:
            raise RuntimeError(f"registered-cell index rail unexpectedly open: {key}")
    if index["semantic_sha256"]!=EXPECTED_INDEX_SEMANTIC:
        raise RuntimeError("registered-cell index semantic drift; rebuild review on live truth")
    if any(str(row.get("cell_id"))==CELL_ID for row in index.get("entries",[])):
        raise RuntimeError("Anneessens already registered; this pre-registration review must not run")

    intersections=[
        {"niscode":nis,"inspire_id":mid,"name_fre":fr,"name_dut":nl,"intersection_area_m2":area,"coverage_ratio":ratio}
        for nis,mid,area,ratio,fr,nl in EXPECTED_MUNICIPALITIES
    ]
    out={
      "schema":"grand-bruxelles-anneessens-canonical-registration-review-v1",
      "status":"READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL",
      "production_base_sha":production_base_sha,
      "cell_id":CELL_ID,"crs":"EPSG:31370","bbox":BBOX,
      "source":{
        "authority":"Paradigm / Brussels-Capital Region","service":"UrbIS vector WFS","license":"CC0-1.0",
        "revision":"content_addressed_no_stable_wfs_release_id",
        "source_semantic_sha256":EXPECTED_SOURCE_SEMANTIC,
        "manifest_sha256":source_lock["manifest_sha256"],"maturity_sha256":source_lock["maturity_sha256"],
        "manifest_source_digest":source_lock["manifest_source_digest"],
        "layer_accounting":EXPECTED_COUNTS,
        "building_ownership":{"ownership_filtered":52,"invalid_ownership_features":0},
      },
      "municipality_boundary":{
        "status":"HOLD_MUNICIPALITY_BOUNDARY_CELL","semantic_sha256":EXPECTED_MUNICIPAL_SEMANTIC,
        "assignment_policy":"retain_all_official_intersections_no_dominant_municipality_canonicalization",
        "cell_area_m2":250000.0,"coverage_sum":1.0,"intersections":intersections,
      },
      "registered_cell_index":{"target_present":False,"registered_cell_count":int(index["registered_cell_count"]),"semantic_sha256":index["semantic_sha256"]},
      "registration_authorized":False,"road_cell_mapping_authorized":False,"runtime_directory_scan_authorized":False,
      "runtime_mount_authorized":False,"rendered_geometry_authorized":False,"collision_authorized":False,
      "safe_spawn_authorized":False,"jouable_promotion_authorized":False,
      "next_action":"generate a separate boundary-aware canonical-manifest candidate preserving all three official municipality intersections; do not mutate the registered-cell index in this review lot",
    }
    canonical=json.dumps(out,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode("utf-8")
    out["semantic_sha256"]=hashlib.sha256(canonical).hexdigest()
    return out

def main() -> None:
    p=argparse.ArgumentParser()
    p.add_argument("--repo-root",type=Path,default=Path("."))
    p.add_argument("--production-base-sha",required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    out=build_review(a.repo_root/"grand-bruxelles-game",a.production_base_sha)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(out,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"ANNEESSENS_CANONICAL_REGISTRATION_REVIEW_OK: status={out['status']} semantic_sha256={out['semantic_sha256']}")
if __name__=="__main__":
    main()
