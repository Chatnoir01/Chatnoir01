#!/usr/bin/env python3
"""Grand Bruxelles continuity selector.

Reads catalog + maturity registry + optional exported SIGNALER tickets.
Oldest open report wins; otherwise run the registry's next upgrade lot.
Never promotes M6 and never mutates city_machine/citygen outputs.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "qa" / "playable_zone_catalog.json"
REGISTRY = ROOT / "data" / "qa" / "zone_maturity_registry.json"
REPORT_SCHEMA = "grand-bruxelles-player-report-v1"
CATALOG_SCHEMAS = {"grand-bruxelles-playable-zone-catalog-v1", "grand-bruxelles-playable-zone-catalog-v2"}
MATURITY_ORDER = {"M0_NON_LISTED":0,"M1_LABO_BRUT":1,"M2_LABO_STABLE":2,"M3_LABO_LOOK":3,"M4_LABO_ALIVE":4,"M5_JOUABLE_READY":5,"M6_JOUABLE":6}

def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict): raise ValueError(f"expected JSON object: {path}")
    return data

def catalog_ids() -> tuple[str, list[str]]:
    data = load_json(CATALOG)
    schema = str(data.get("schema", ""))
    if schema not in CATALOG_SCHEMAS: raise ValueError(f"unsupported catalogue schema: {schema}")
    rows = data.get("zones", [])
    ids = [str(r.get("id", "")) for r in rows if isinstance(r, dict)]
    if len(ids) != 7 or len(set(ids)) != 7: raise ValueError(f"catalogue must contain exactly seven unique zones, got {ids}")
    return schema, ids

def registry_rows() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    data = load_json(REGISTRY); by_id = {}
    for raw in data.get("zones", []):
        if not isinstance(raw, dict): raise ValueError("registry zone row must be an object")
        zid = str(raw.get("zone_id", "")); maturity = str(raw.get("maturity", "")); target = str(raw.get("target_maturity", ""))
        if not zid or zid in by_id: raise ValueError(f"invalid/duplicate registry zone_id: {zid!r}")
        if maturity not in MATURITY_ORDER or target not in MATURITY_ORDER: raise ValueError(f"unknown maturity for {zid}: {maturity}/{target}")
        if MATURITY_ORDER[maturity] > MATURITY_ORDER[target]: raise ValueError(f"maturity exceeds target for {zid}")
        if target == "M6_JOUABLE" and zid != "midi": raise ValueError(f"automation may not target M6 for {zid}")
        lots = raw.get("active_defect_lots", [])
        if not isinstance(lots, list) or len(lots) != len(set(map(str, lots))): raise ValueError(f"duplicate active defect lot in {zid}")
        by_id[zid] = raw
    return data, by_id

def read_reports(report_dir: Path | None) -> list[dict[str, Any]]:
    if report_dir is None: return []
    if not report_dir.exists(): raise FileNotFoundError(report_dir)
    reports=[]
    for path in sorted(report_dir.glob("*.gbreport.json")):
        d=load_json(path)
        if d.get("schema") != REPORT_SCHEMA or d.get("status") != "open": continue
        zone=d.get("zone", {})
        if not isinstance(zone, dict) or not str(zone.get("id", "")): raise ValueError(f"open report has no zone id: {path}")
        d["_source_path"]=path.as_posix(); reports.append(d)
    reports.sort(key=lambda r:(int(r.get("captured_unix",0)),str(r.get("id",""))))
    return reports

def validate() -> None:
    schema, ids = catalog_ids(); reg, by_id = registry_rows()
    if set(ids) != set(by_id): raise ValueError(f"catalogue/registry zone mismatch: catalog={ids} registry={sorted(by_id)}")
    if reg.get("catalog_schema") not in (None, schema): raise ValueError("registry/catalog schema drift")
    midi=by_id["midi"]
    if midi.get("maturity") != "M6_JOUABLE" or midi.get("target_maturity") != "M6_JOUABLE": raise ValueError("Midi human JOUABLE baseline may not silently regress")
    print(f"CONTINUITY_REGISTRY_OK zones=7 catalog={schema} midi_baseline=M6 automation_ceiling=M5")

def next_lot(zone_id: str, report_dir: Path | None) -> dict[str, Any]:
    _, by_id = registry_rows()
    if zone_id not in by_id: raise KeyError(zone_id)
    row=by_id[zone_id]
    reports=[r for r in read_reports(report_dir) if str((r.get("zone") or {}).get("id","")) == zone_id]
    if reports:
        r=reports[0]
        return {"zone_id":zone_id,"decision":"fix_oldest_open_report","report_id":str(r.get("id","")),"captured_unix":int(r.get("captured_unix",0)),"note":str(r.get("note","")),"source_path":str(r.get("_source_path","")),"maturity":row["maturity"],"target_maturity":row["target_maturity"]}
    if row["maturity"] == "M6_JOUABLE": return {"zone_id":zone_id,"decision":"protect_human_jouable_baseline","next_lot":"protect_baseline_only"}
    if row["maturity"] == "M5_JOUABLE_READY": return {"zone_id":zone_id,"decision":"wait_human","next_lot":"human_jouable_decision"}
    return {"zone_id":zone_id,"decision":"run_next_upgrade_lot","maturity":row["maturity"],"target_maturity":row["target_maturity"],"next_lot":row["next_lot"],"report_sync_required_before_M5":report_dir is None}

def main() -> int:
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="command",required=True); sub.add_parser("validate")
    n=sub.add_parser("next"); n.add_argument("--zone",required=True); n.add_argument("--reports-dir",type=Path); a=p.parse_args()
    validate()
    if a.command == "next": print(json.dumps(next_lot(a.zone,a.reports_dir),ensure_ascii=False,sort_keys=True))
    return 0
if __name__ == "__main__": raise SystemExit(main())
