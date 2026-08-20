#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys

import city_machine as cm
import finish_materials as fm


def run(zone_id: str, dry_run: bool = False) -> int:
    print(f"CITY_MACHINE_FAMILY START finish_materials zone={zone_id}")
    fm.materialize(zone_id, dry_run=dry_run)
    if not dry_run:
        fm.gate(zone_id)
    print(
        f"CITY_MACHINE_FAMILY END finish_materials zone={zone_id} "
        f"gate={fm.GATE if not dry_run else 'deferred'}"
    )
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
