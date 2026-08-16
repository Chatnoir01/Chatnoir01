#!/usr/bin/env python3
"""Build a fail-closed candidate package for one authoritative UrbIS cell."""
from __future__ import annotations
import argparse, hashlib, json, math
from pathlib import Path
from typing import Any

from bootstrap_cell_maturity import GATES as REQUIRED_GATES

FORMAT = "grand-bruxelles-cell-candidate-package-v1"


def digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def read_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict): raise ValueError(f"expected JSON object: {path}")
    return value


def polygon_record(feature: dict[str, Any], cell_id: str) -> dict[str, Any] | None:
    props=feature.get("properties") or {}; geometry=feature.get("geometry") or {}; building_id=props.get("INSPIRE_ID")
    if not building_id or geometry.get("type") != "Polygon": return None
    coords=geometry.get("coordinates") or []
    if not coords or not isinstance(coords[0],list) or len(coords[0]) < 4: return None
    points=[]
    for point in coords[0]:
        if not isinstance(point,list) or len(point)<2: return None
        x,y=float(point[0]),float(point[1])
        if not math.isfinite(x) or not math.isfinite(y): return None
        points.append([round(x,3),round(y,3)])
    xs=[p[0] for p in points]; ys=[p[1] for p in points]
    row={"building_id":str(building_id),"cell_id":cell_id,"block_id":props.get("BLOCK_ID"),"area_m2":props.get("AREA"),"bbox_31370":[min(xs),min(ys),max(xs),max(ys)],"vertex_count":len(points),"footprint_31370":points,"footprint_digest":digest(points),"height_m":None,"street_facing_edge":None,"facade_recipe_digest":None,"runtime_approved":False}
    row["record_digest"]=digest(row); return row


def maturity_status(path: Path | None, cell_id: str) -> tuple[str,list[str],dict[str,Any]]:
    if path is None or not path.exists(): return "EVIDENCE_PENDING",["maturity_manifest_missing"],{}
    maturity=read_object(path)
    if maturity.get("cell_id") != cell_id: return "QUARANTINE",["maturity_cell_id_mismatch"],maturity
    if maturity.get("crs") != "EPSG:31370": return "QUARANTINE",["maturity_crs_mismatch"],maturity
    if not (maturity.get("geometry") or {}).get("authoritative_geometry_ready",False): return "QUARANTINE",["authoritative_geometry_not_ready"],maturity
    gates=(maturity.get("maturity") or {}).get("gates") or {}; blockers=[gate for gate in REQUIRED_GATES if gates.get(gate) is not True]
    return ("EVIDENCE_PENDING",blockers,maturity) if blockers else ("RUNTIME_GATE_COMPLETE",[],maturity)


def build(cell_dir: Path, maturity_path: Path | None) -> dict[str,Any]:
    cell_id=cell_dir.name; source_manifest_path=cell_dir/"manifest.json"; buildings_path=cell_dir/"raw"/"buildings.geojson"
    if not source_manifest_path.exists(): raise ValueError("authoritative source manifest missing")
    source_manifest=read_object(source_manifest_path)
    if maturity_path is None:
        sidecar=cell_dir/"maturity.json"
        if sidecar.exists(): maturity_path=sidecar

    records={}; invalid_features=0; buildings_source_present=buildings_path.exists()
    if buildings_source_present:
        collection=read_object(buildings_path)
        if collection.get("type") != "FeatureCollection": raise ValueError("buildings source is not a FeatureCollection")
        for feature in collection.get("features") or []:
            row=polygon_record(feature,cell_id)
            if row is None: invalid_features+=1; continue
            if row["building_id"] in records: raise ValueError(f"duplicate INSPIRE_ID in cell: {row['building_id']}")
            records[row["building_id"]]=row

    state,blockers,maturity=maturity_status(maturity_path,cell_id)
    if not buildings_source_present:
        state="QUARANTINE"; blockers=sorted(set(blockers+["authoritative_buildings_missing"]))
    if invalid_features: state="QUARANTINE"; blockers=sorted(set(blockers+["invalid_building_features_present"]))
    if buildings_source_present and not records: state="QUARANTINE"; blockers=sorted(set(blockers+["no_valid_authoritative_buildings"]))
    buildings=[records[k] for k in sorted(records)]
    package={"format":FORMAT,"cell_id":cell_id,"crs":"EPSG:31370","state":state,"blockers":blockers,"authority":{"geometry":"UrbIS raw EPSG:31370 building footprints","buildings_source_present":buildings_source_present,"source_manifest_digest":digest(source_manifest),"maturity_manifest_digest":digest(maturity) if maturity else None},"summary":{"valid_buildings":len(buildings),"invalid_features":invalid_features,"total_vertices":sum(row["vertex_count"] for row in buildings),"runtime_approved_buildings":0},"buildings":buildings,"promotion_policy":"no_runtime_mutation_until_full_regional_maturity_contract_passes"}
    package["package_digest"]=digest(package); return package


def main() -> None:
    p=argparse.ArgumentParser(); p.add_argument("--cell-dir",type=Path,required=True); p.add_argument("--maturity",type=Path); p.add_argument("--output",type=Path,required=True); a=p.parse_args()
    package=build(a.cell_dir,a.maturity); a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(package,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8")
    print("CELL_CANDIDATE_PACKAGE_OK",package["cell_id"],package["state"],package["summary"],package["package_digest"])

if __name__ == "__main__": main()
