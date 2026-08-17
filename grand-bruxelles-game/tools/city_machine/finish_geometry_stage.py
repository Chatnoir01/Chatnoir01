#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

import city_machine as cm

GEOMETRY_KINDS = {"resolve_zone", "materialize_geojson"}
GEOMETRY_GATES = {"G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets"}


def run(zone_id: str, dry_run: bool = False) -> int:
    registry = cm.load_registry()
    catalog = cm.read_json(cm.CATALOG)
    zone = cm.resolve_zone(catalog, zone_id)
    profile = (registry.get("zone_profiles") or {}).get(zone_id)
    if not profile:
        raise cm.MachineError(f"zone '{zone_id}' is not enabled in city_machine")
    manifest = cm.source_contract(profile)

    print(f"CITY_MACHINE_FAMILY START geometry zone={zone_id}")
    for layer in registry["layers"]:
        if zone_id not in layer.get("enabled_zones", []):
            continue
        if layer.get("kind") not in GEOMETRY_KINDS:
            continue
        lid = str(layer["layer_id"])
        print(f"CITY_MACHINE_LAYER START {lid}")
        if layer["kind"] == "materialize_geojson" and not dry_run:
            cm.materialize(layer, profile, manifest)
        print(f"CITY_MACHINE_LAYER END {lid}")

    if dry_run:
        print(f"CITY_MACHINE_FAMILY END geometry zone={zone_id} mode=dry-run")
        return 0

    for layer in registry["layers"]:
        if zone_id not in layer.get("enabled_zones", []):
            continue
        gate = layer.get("gate")
        if gate not in GEOMETRY_GATES:
            continue
        if gate == "G1_sources_crs":
            cm.gate_g1(layer, profile)
        elif gate == "G2_spawn_ground":
            cm.gate_spawn(zone, profile, manifest)
        elif gate == "G3_buildings_streets":
            cm.gate_content(profile)

    print(f"CITY_MACHINE_FAMILY END geometry zone={zone_id} gates=G1,G2,G3")
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
