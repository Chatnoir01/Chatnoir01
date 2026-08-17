#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

import city_machine as cm

ENV_LAYER_ID = "osm_environment_points"
ENV_GATE = "G5_osm_environment"


def run(zone_id: str, dry_run: bool = False) -> int:
    registry = cm.load_registry()
    catalog = cm.read_json(cm.CATALOG)
    cm.resolve_zone(catalog, zone_id)
    profile = (registry.get("zone_profiles") or {}).get(zone_id)
    if not profile:
        raise cm.MachineError(f"zone '{zone_id}' is not enabled in city_machine")
    manifest = cm.source_contract(profile)

    layer = next(
        (row for row in registry["layers"] if row.get("layer_id") == ENV_LAYER_ID and zone_id in row.get("enabled_zones", [])),
        None,
    )
    if layer is None:
        print(f"CITY_MACHINE_FAMILY SKIP osm_environment status=disabled reason=no enabled OSM environment layer for {zone_id}")
        return 0

    print(f"CITY_MACHINE_FAMILY START osm_environment zone={zone_id}")
    print(f"CITY_MACHINE_LAYER START {ENV_LAYER_ID}")
    if not dry_run:
        cm.materialize_osm(layer, profile, zone_id)
    print(f"CITY_MACHINE_LAYER END {ENV_LAYER_ID}")

    if not dry_run:
        cm.gate_osm_environment(zone_id, profile, manifest)
    print(f"CITY_MACHINE_FAMILY END osm_environment zone={zone_id} gate={ENV_GATE if not dry_run else 'deferred'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        return run(args.zone, args.dry_run)
    except cm.GateError as exc:
        print(f"CITY_MACHINE_GATE FAIL {exc.gate} detail={exc.detail}", file=sys.stderr)
        return 3
    except cm.MachineError as exc:
        print(f"CITY_MACHINE_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
