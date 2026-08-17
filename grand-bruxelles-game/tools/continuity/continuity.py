#!/usr/bin/env python3
"""Grand Bruxelles continuity selector.

Phase 1 contract:
- read the playable zone catalogue and durable maturity registry;
- optionally ingest exported SIGNALER `.gbreport.json` files from a supplied directory;
- choose the next lot deterministically: oldest open report first, otherwise registry next_lot;
- never promote M6 and never mutate city_machine/citygen runtime outputs.

This tool is intentionally orchestration-only. It does not create geometry or edit the
playable catalogue. Later phases may call city_machine for rebuilds, but must not bypass it.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "qa" / "playable_zone_catalog.json"
REGISTRY = ROOT / "data" / "qa" / "zone_maturity_registry.json"
REPORT_SCHEMA = "grand-bruxelles-player-report-v1"
MATURITY_ORDER = {
    "M0_NON_LISTED": 0,
    "M1_LABO_BRUT": 1,
    "M2_LABO_STABLE": 2,
    "M3_LABO_LOOK": 3,
    "M4_LABO_ALIVE": 4,
    "M5_JOUABLE_READY": 5,
    "M6_JOUABLE": 6,
}


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"expected JSON object: {path}")
    return data


def catalog_ids() -> list[str]:
    data = load_json(CATALOG)
    rows = data.get("zones", [])
    ids = [str(row.get("id", "")) for row in rows if isinstance(row, dict)]
    if len(ids) != 7 or len(set(ids)) != len(ids):
        raise ValueError(f"catalogue must contain exactly seven unique zones, got {ids}")
    return ids


def registry_rows() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    data = load_json(REGISTRY)
    rows = data.get("zones", [])
    by_id: dict[str, dict[str, Any]] = {}
    for raw in rows:
        if not isinstance(raw, dict):
            raise ValueError("registry zone row must be an object")
        zone_id = str(raw.get("zone_id", ""))
        if not zone_id or zone_id in by_id:
            raise ValueError(f"invalid/duplicate registry zone_id: {zone_id!r}")
        maturity = str(raw.get("maturity", ""))
        target = str(raw.get("target_maturity", ""))
        if maturity not in MATURITY_ORDER or target not in MATURITY_ORDER:
            raise ValueError(f"unknown maturity for {zone_id}: {maturity}/{target}")
        if MATURITY_ORDER[maturity] > MATURITY_ORDER[target]:
            raise ValueError(f"maturity exceeds target for {zone_id}")
        if target == "M6_JOUABLE" and zone_id != "midi":
            raise ValueError(f"automation may not target M6 for {zone_id}")
        lots = raw.get("active_defect_lots", [])
        if not isinstance(lots, list) or len(lots) != len(set(map(str, lots))):
            raise ValueError(f"duplicate active defect lot in {zone_id}")
        by_id[zone_id] = raw
    return data, by_id


def read_reports(report_dir: Path | None) -> list[dict[str, Any]]:
    if report_dir is None:
        return []
    if not report_dir.exists():
        raise FileNotFoundError(f"report directory does not exist: {report_dir}")
    reports: list[dict[str, Any]] = []
    for path in sorted(report_dir.glob("*.gbreport.json")):
        data = load_json(path)
        if data.get("schema") != REPORT_SCHEMA or data.get("status") != "open":
            continue
        zone = data.get("zone", {})
        if not isinstance(zone, dict) or not str(zone.get("id", "")):
            raise ValueError(f"open report has no zone id: {path}")
        data["_source_path"] = path.as_posix()
        reports.append(data)
    reports.sort(key=lambda row: (int(row.get("captured_unix", 0)), str(row.get("id", ""))))
    return reports


def validate() -> None:
    ids = catalog_ids()
    _, by_id = registry_rows()
    if ids != [zone_id for zone_id in ids if zone_id in by_id] or set(ids) != set(by_id):
        raise ValueError(f"catalogue/registry zone mismatch: catalog={ids} registry={sorted(by_id)}")
    midi = by_id["midi"]
    if midi.get("maturity") != "M6_JOUABLE" or midi.get("target_maturity") != "M6_JOUABLE":
        raise ValueError("Midi human JOUABLE baseline may not silently regress")
    print("CONTINUITY_REGISTRY_OK zones=7 midi_baseline=M6 automation_ceiling=M5")


def next_lot(zone_id: str, report_dir: Path | None) -> dict[str, Any]:
    _, by_id = registry_rows()
    if zone_id not in by_id:
        raise KeyError(f"unknown zone: {zone_id}")
    row = by_id[zone_id]
    reports = [r for r in read_reports(report_dir) if str((r.get("zone") or {}).get("id", "")) == zone_id]
    if reports:
        oldest = reports[0]
        return {
            "zone_id": zone_id,
            "decision": "fix_oldest_open_report",
            "report_id": str(oldest.get("id", "")),
            "captured_unix": int(oldest.get("captured_unix", 0)),
            "note": str(oldest.get("note", "")),
            "source_path": str(oldest.get("_source_path", "")),
            "maturity": row["maturity"],
            "target_maturity": row["target_maturity"],
        }
    if row["maturity"] == "M6_JOUABLE":
        return {"zone_id": zone_id, "decision": "protect_human_jouable_baseline", "next_lot": "protect_baseline_only"}
    if row["maturity"] == "M5_JOUABLE_READY":
        return {"zone_id": zone_id, "decision": "wait_human", "next_lot": "human_jouable_decision"}
    return {
        "zone_id": zone_id,
        "decision": "run_next_upgrade_lot",
        "maturity": row["maturity"],
        "target_maturity": row["target_maturity"],
        "next_lot": row["next_lot"],
        "report_sync_required_before_M5": report_dir is None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    choose = sub.add_parser("next")
    choose.add_argument("--zone", required=True)
    choose.add_argument("--reports-dir", type=Path)
    args = parser.parse_args()

    if args.command == "validate":
        validate()
        return 0
    validate()
    print(json.dumps(next_lot(args.zone, args.reports_dir), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
