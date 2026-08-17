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
REPORT_SYNC_SCHEMA = "grand-bruxelles-continuity-report-sync-v1"
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
    if not report_dir.exists() or not report_dir.is_dir(): raise FileNotFoundError(report_dir)
    reports=[]
    for path in sorted(report_dir.glob("*.gbreport.json")):
        d=load_json(path)
        if d.get("schema") != REPORT_SCHEMA: raise ValueError(f"unsupported report schema in {path}: {d.get('schema')!r}")
        if d.get("status") != "open": raise ValueError(f"expected OPEN report export in {path}, got status={d.get('status')!r}")
        zone=d.get("zone", {})
        if not isinstance(zone, dict) or not str(zone.get("id", "")): raise ValueError(f"open report has no zone id: {path}")
        if not str(d.get("id", "")): raise ValueError(f"open report has no id: {path}")
        d["_source_path"]=path.as_posix(); reports.append(d)
    reports.sort(key=lambda r:(int(r.get("captured_unix",0)),str(r.get("id",""))))
    return reports

def validate_sync_snapshot(path: Path, expected_zone: str | None = None) -> dict[str, Any]:
    data=load_json(path)
    if data.get("schema") != REPORT_SYNC_SCHEMA: raise ValueError(f"unsupported report sync schema: {data.get('schema')!r}")
    if data.get("state") != "complete_snapshot": raise ValueError("report sync snapshot must be complete_snapshot")
    zone_id=str(data.get("zone_id", ""))
    if not zone_id: raise ValueError("report sync snapshot missing zone_id")
    if expected_zone is not None and zone_id != expected_zone: raise ValueError(f"report sync zone mismatch: expected {expected_zone}, got {zone_id}")
    rows=data.get("open_reports", [])
    if not isinstance(rows, list): raise ValueError("report sync open_reports must be a list")
    if int(data.get("open_count", -1)) != len(rows): raise ValueError("report sync open_count mismatch")
    seen=set()
    for row in rows:
        if not isinstance(row, dict): raise ValueError("report sync report row must be an object")
        rid=str(row.get("id", ""))
        if not rid or rid in seen: raise ValueError(f"invalid/duplicate report id in sync snapshot: {rid!r}")
        if str(row.get("zone_id", "")) != zone_id: raise ValueError(f"foreign zone report in sync snapshot: {rid}")
        seen.add(rid)
    return data

def sync_snapshot(zone_id: str, report_dir: Path) -> dict[str, Any]:
    _, by_id=registry_rows()
    if zone_id not in by_id: raise KeyError(zone_id)
    reports=read_reports(report_dir)
    foreign=[r for r in reports if str((r.get("zone") or {}).get("id", "")) != zone_id]
    if foreign:
        ids=[str(r.get("id", "")) for r in foreign]
        raise ValueError(f"report export contains foreign-zone OPEN reports for {zone_id}: {ids}")
    rows=[]
    for r in reports:
        rows.append({
            "id":str(r.get("id", "")),
            "zone_id":zone_id,
            "captured_unix":int(r.get("captured_unix", 0)),
            "note":str(r.get("note", "")),
            "source_file":Path(str(r.get("_source_path", ""))).name,
        })
    return {
        "schema":REPORT_SYNC_SCHEMA,
        "state":"complete_snapshot",
        "zone_id":zone_id,
        "source":"exported_SIGNALER_open_directory",
        "open_count":len(rows),
        "open_reports":rows,
        "oldest_open_report_id":rows[0]["id"] if rows else None,
        "maturity_at_sync":by_id[zone_id]["maturity"],
        "target_maturity":by_id[zone_id]["target_maturity"],
        "zero_open_is_proven":len(rows)==0,
    }

def reports_from_sync(path: Path, zone_id: str) -> list[dict[str, Any]]:
    data=validate_sync_snapshot(path, zone_id)
    reports=[]
    for row in data.get("open_reports", []):
        reports.append({
            "id":str(row.get("id", "")),
            "captured_unix":int(row.get("captured_unix", 0)),
            "note":str(row.get("note", "")),
            "zone":{"id":zone_id},
            "_source_path":path.as_posix(),
        })
    reports.sort(key=lambda r:(int(r.get("captured_unix",0)),str(r.get("id",""))))
    return reports

def validate() -> None:
    schema, ids = catalog_ids(); reg, by_id = registry_rows()
    if set(ids) != set(by_id): raise ValueError(f"catalogue/registry zone mismatch: catalog={ids} registry={sorted(by_id)}")
    if reg.get("catalog_schema") not in (None, schema): raise ValueError("registry/catalog schema drift")
    midi=by_id["midi"]
    if midi.get("maturity") != "M6_JOUABLE" or midi.get("target_maturity") != "M6_JOUABLE": raise ValueError("Midi human JOUABLE baseline may not silently regress")
    print(f"CONTINUITY_REGISTRY_OK zones=7 catalog={schema} midi_baseline=M6 automation_ceiling=M5")

def next_lot(zone_id: str, report_dir: Path | None, report_sync: Path | None) -> dict[str, Any]:
    _, by_id = registry_rows()
    if zone_id not in by_id: raise KeyError(zone_id)
    if report_dir is not None and report_sync is not None: raise ValueError("choose either --reports-dir or --report-sync, not both")
    row=by_id[zone_id]
    sync_complete=False
    if report_sync is not None:
        reports=reports_from_sync(report_sync, zone_id)
        sync_complete=True
    else:
        reports=[r for r in read_reports(report_dir) if str((r.get("zone") or {}).get("id","")) == zone_id]
        sync_complete=report_dir is not None
    if reports:
        r=reports[0]
        return {"zone_id":zone_id,"decision":"fix_oldest_open_report","report_id":str(r.get("id","")),"captured_unix":int(r.get("captured_unix",0)),"note":str(r.get("note","")),"source_path":str(r.get("_source_path","")),"maturity":row["maturity"],"target_maturity":row["target_maturity"],"report_sync_complete":sync_complete}
    if row["maturity"] == "M6_JOUABLE": return {"zone_id":zone_id,"decision":"protect_human_jouable_baseline","next_lot":"protect_baseline_only"}
    if row["maturity"] == "M5_JOUABLE_READY": return {"zone_id":zone_id,"decision":"wait_human","next_lot":"human_jouable_decision"}
    return {"zone_id":zone_id,"decision":"run_next_upgrade_lot","maturity":row["maturity"],"target_maturity":row["target_maturity"],"next_lot":row["next_lot"],"report_sync_required_before_M5":not sync_complete,"report_sync_complete":sync_complete}

def main() -> int:
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="command",required=True); sub.add_parser("validate")
    n=sub.add_parser("next"); n.add_argument("--zone",required=True); n.add_argument("--reports-dir",type=Path); n.add_argument("--report-sync",type=Path)
    s=sub.add_parser("sync"); s.add_argument("--zone",required=True); s.add_argument("--reports-dir",required=True,type=Path); s.add_argument("--out",required=True,type=Path)
    a=p.parse_args(); validate()
    if a.command == "next": print(json.dumps(next_lot(a.zone,a.reports_dir,a.report_sync),ensure_ascii=False,sort_keys=True))
    elif a.command == "sync":
        payload=sync_snapshot(a.zone,a.reports_dir)
        a.out.parent.mkdir(parents=True,exist_ok=True)
        a.out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        print(f"CONTINUITY_REPORT_SYNC_OK zone={a.zone} open={payload['open_count']} zero_open_is_proven={str(payload['zero_open_is_proven']).lower()} out={a.out}")
    return 0
if __name__ == "__main__": raise SystemExit(main())
