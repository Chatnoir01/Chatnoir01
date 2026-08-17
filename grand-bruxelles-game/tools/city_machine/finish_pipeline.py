#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
FINISH_REGISTRY = HERE / "finish_registry.json"
BASE_REGISTRY = HERE / "registry.json"
CITY_MACHINE = HERE / "city_machine.py"
EXPECTED_FAMILIES = ["geometry", "osm_environment", "finish_materials", "life", "proof"]
VALID_STATUS = {"wired", "disabled", "missing", "blocked"}


class FinishPipelineError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise FinishPipelineError(f"expected object: {path}")
    return value


def validate_finish_registry(zone_id: str) -> dict[str, Any]:
    reg = read_json(FINISH_REGISTRY)
    if reg.get("schema") != "grand-bruxelles-city-machine-finish-registry-v1":
        raise FinishPipelineError("unsupported finish registry")
    if reg.get("pilot_zone") != zone_id:
        raise FinishPipelineError(f"pilot locked to {reg.get('pilot_zone')}, got {zone_id}")
    if reg.get("auto_jouable") is not False:
        raise FinishPipelineError("auto JOUABLE must remain false")
    rows = reg.get("families")
    if not isinstance(rows, list):
        raise FinishPipelineError("families must be a list")
    ids = [str(row.get("family_id", "")) for row in rows if isinstance(row, dict)]
    if ids != EXPECTED_FAMILIES:
        raise FinishPipelineError(f"family order mismatch: {ids}")
    for row in rows:
        status = str(row.get("status", ""))
        if status not in VALID_STATUS:
            raise FinishPipelineError(f"invalid status for {row.get('family_id')}: {status}")
        if status != "wired" and not str(row.get("reason", "")).strip():
            raise FinishPipelineError(f"non-wired family missing reason: {row.get('family_id')}")
    return reg


def log_disabled_base_layers(zone_id: str) -> None:
    reg = read_json(BASE_REGISTRY)
    for row in reg.get("layers", []):
        if not isinstance(row, dict):
            continue
        if zone_id in row.get("enabled_zones", []):
            continue
        reason = str(row.get("disabled_reason") or "not_enabled_for_zone")
        print(f"CITY_MACHINE_LAYER SKIP {row.get('layer_id')} reason={reason}")


def run(zone_id: str, dry_run: bool) -> int:
    reg = validate_finish_registry(zone_id)
    print(f"CITY_MACHINE_FINISH_START zone={zone_id} auto_jouable=false")
    for row in reg["families"]:
        family = str(row["family_id"])
        status = str(row["status"])
        if status == "wired":
            print(f"CITY_MACHINE_FAMILY READY {family} status=wired")
        else:
            print(f"CITY_MACHINE_FAMILY SKIP {family} status={status} reason={row['reason']}")
    log_disabled_base_layers(zone_id)
    cmd = [sys.executable, str(CITY_MACHINE), "build", "--zone", zone_id]
    if dry_run:
        cmd.append("--dry-run")
    result = subprocess.run(cmd, cwd=PROJECT)
    if result.returncode != 0:
        print(f"CITY_MACHINE_FINISH_FAIL zone={zone_id} delegated_rc={result.returncode}", file=sys.stderr)
        return result.returncode
    print(f"CITY_MACHINE_FINISH_END zone={zone_id} result=LABO_DATA_READY promotion=false")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--zone", required=True)
    build.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        return run(args.zone, args.dry_run)
    except (OSError, json.JSONDecodeError, FinishPipelineError) as exc:
        print(f"CITY_MACHINE_FINISH_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
