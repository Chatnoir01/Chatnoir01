#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

import city_machine as cm
import finish_materials as fm

PROOF_GATES = [
    "G1_sources_crs",
    "G2_spawn_ground",
    "G3_buildings_streets",
    "G4_runtime_finish",
    "G5_osm_environment",
    "G6_finish_materials",
]


def run(zone_id: str) -> int:
    registry = cm.load_registry()
    catalog = cm.read_json(cm.CATALOG)
    zone = cm.resolve_zone(catalog, zone_id)
    profile = (registry.get("zone_profiles") or {}).get(zone_id)
    if not profile:
        raise cm.MachineError(f"zone '{zone_id}' is not enabled in city_machine")
    manifest = cm.source_contract(profile)

    by_gate = {row.get("gate"): row for row in registry["layers"] if row.get("gate")}
    required_registry_gates = PROOF_GATES[:5]
    missing = [gate for gate in required_registry_gates if gate not in by_gate]
    if missing:
        raise cm.MachineError(f"proof gates missing: {missing}")

    print(f"CITY_MACHINE_FAMILY START proof zone={zone_id}")
    cm.gate_g1(by_gate["G1_sources_crs"], profile)
    cm.gate_spawn(zone, profile, manifest)
    cm.gate_content(profile)
    cm.gate_finish(by_gate["G4_runtime_finish"])
    cm.gate_osm_environment(zone_id, profile, manifest)
    fm.gate(zone_id)
    print(f"CITY_MACHINE_FAMILY END proof zone={zone_id} gates={','.join(PROOF_GATES)} promotion=false")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    args = parser.parse_args()
    try:
        return run(args.zone)
    except cm.GateError as exc:
        print(f"CITY_MACHINE_GATE FAIL {exc.gate} detail={exc.detail}", file=sys.stderr)
        return 3
    except cm.MachineError as exc:
        print(f"CITY_MACHINE_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
