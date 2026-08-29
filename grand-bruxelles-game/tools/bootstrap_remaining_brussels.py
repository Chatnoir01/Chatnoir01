#!/usr/bin/env python3
"""Bootstrap official boundary + 500 m cell manifests for remaining Brussels zones.

This orchestrator deliberately calls the small, testable tools already present in
this repository. It can process one zone, one wave, or every municipality in the
remaining-Brussels catalog. Network access is only required for the UrbIS fetch.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "data" / "remaining_brussels_zones.json"
BOUNDARY_TOOL = ROOT / "tools" / "fetch_urbis_municipality.py"
CELL_TOOL = ROOT / "tools" / "make_zone_cells.py"


def load_catalog(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    zones = data.get("zones")
    if not isinstance(zones, list) or not zones:
        raise ValueError("catalog must contain a non-empty zones list")
    return data


def choose_zones(catalog: dict, zone_ids: list[str], wave: str | None, all_zones: bool) -> list[dict]:
    zones = catalog["zones"]
    by_id = {zone["id"]: zone for zone in zones}

    if all_zones:
        return sorted(zones, key=lambda zone: zone.get("priority", 9999))
    if zone_ids:
        missing = [zone_id for zone_id in zone_ids if zone_id not in by_id]
        if missing:
            raise KeyError(f"unknown zone id(s): {', '.join(missing)}")
        return [by_id[zone_id] for zone_id in zone_ids]
    if wave:
        selected = [zone for zone in zones if zone.get("wave") == wave]
        if not selected:
            raise KeyError(f"no zones found for wave {wave!r}")
        return sorted(selected, key=lambda zone: zone.get("priority", 9999))
    raise ValueError("select at least one --zone, --wave, or --all")


def commands_for_zone(zone: dict, output_root: Path, cell_size: float) -> list[list[str]]:
    zone_id = zone["id"]
    boundary = output_root / "boundaries" / f"{zone_id}.geojson"
    manifest = output_root / "cells" / f"{zone_id}.json"
    return [
        [
            sys.executable,
            str(BOUNDARY_TOOL),
            "--name",
            zone["name"],
            "--output",
            str(boundary),
        ],
        [
            sys.executable,
            str(CELL_TOOL),
            "--boundary",
            str(boundary),
            "--zone-id",
            zone_id,
            "--cell-size",
            str(cell_size),
            "--output",
            str(manifest),
        ],
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap official remaining-Brussels work cells")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output-root", type=Path, default=ROOT / "data" / "processed" / "remaining_brussels")
    parser.add_argument("--zone", action="append", dest="zone_ids", default=[])
    parser.add_argument("--wave", choices=["R1", "R2", "R3"])
    parser.add_argument("--all", action="store_true", dest="all_zones")
    parser.add_argument("--cell-size", type=float, default=500.0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.cell_size <= 0:
        parser.error("--cell-size must be greater than zero")
    selectors = int(bool(args.zone_ids)) + int(bool(args.wave)) + int(args.all_zones)
    if selectors != 1:
        parser.error("use exactly one selector: --zone, --wave, or --all")

    catalog = load_catalog(args.catalog)
    zones = choose_zones(catalog, args.zone_ids, args.wave, args.all_zones)
    args.output_root.mkdir(parents=True, exist_ok=True)

    run_manifest = {
        "format": "grand-bruxelles-bootstrap-run-v1",
        "catalog": str(args.catalog),
        "output_root": str(args.output_root),
        "cell_size_m": args.cell_size,
        "zones": [],
    }

    for zone in zones:
        commands = commands_for_zone(zone, args.output_root, args.cell_size)
        print(f"[{zone['id']}] {zone['name']}")
        for command in commands:
            print("  " + " ".join(command))
            if not args.dry_run:
                subprocess.run(command, check=True, cwd=ROOT)
        run_manifest["zones"].append({"id": zone["id"], "name": zone["name"], "commands": commands})

    run_path = args.output_root / "bootstrap_manifest.json"
    run_path.write_text(json.dumps(run_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"bootstrap manifest -> {run_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
