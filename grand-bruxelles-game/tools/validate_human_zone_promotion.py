#!/usr/bin/env python3
"""Fail closed on automated LABO-family -> JOUABLE catalog promotion.

This validator compares the PR base catalog with the proposed catalog and
refuses any new JOUABLE state. Runtime-local player reports remain useful human
witnesses, but repository CI never treats local client state as global truth.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCHEMA_V1 = "grand-bruxelles-playable-zone-catalog-v1"
SCHEMA_V2 = "grand-bruxelles-playable-zone-catalog-v2"
ALLOWED_SCHEMAS = {SCHEMA_V1, SCHEMA_V2}
ALLOWED_QUALITIES = {"LABO", "LABO_BRUT", "JOUABLE"}
BLOCK_MARKER = "HUMAN_PROMOTION_REQUIRED"
OK_MARKER = "HUMAN_PROMOTION_GATE_OK"


def _load_catalog(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read catalog {path}: {exc}") from exc
    if not isinstance(data, dict) or data.get("schema") not in ALLOWED_SCHEMAS:
        raise ValueError(f"invalid catalog schema in {path}")
    zones = data.get("zones")
    if not isinstance(zones, list):
        raise ValueError(f"invalid zones list in {path}")
    return data


def _zone_map(catalog: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    schema = catalog.get("schema")
    for raw in catalog["zones"]:
        if not isinstance(raw, dict):
            raise ValueError("zone entry is not an object")
        zone_id = str(raw.get("id", "")).strip()
        quality = str(raw.get("quality", "")).strip()
        if not zone_id:
            raise ValueError("zone id is empty")
        if zone_id in result:
            raise ValueError(f"duplicate zone id: {zone_id}")
        if quality not in ALLOWED_QUALITIES:
            raise ValueError(f"unsupported quality for {zone_id}: {quality}")
        if schema == SCHEMA_V1 and quality == "LABO_BRUT":
            raise ValueError(f"LABO_BRUT requires catalog v2 for {zone_id}")
        result[zone_id] = quality
    return result


def blocked_promotions(base: dict[str, Any], head: dict[str, Any]) -> list[str]:
    before = _zone_map(base)
    after = _zone_map(head)
    blocked: list[str] = []
    for zone_id, new_quality in after.items():
        if new_quality != "JOUABLE":
            continue
        old_quality = before.get(zone_id)
        if old_quality != "JOUABLE":
            blocked.append(zone_id)
    return sorted(blocked)


def validate(base_path: Path, head_path: Path) -> int:
    try:
        base = _load_catalog(base_path)
        head = _load_catalog(head_path)
        blocked = blocked_promotions(base, head)
    except ValueError as exc:
        print(f"PROMOTION_GATE_INVALID: {exc}", file=sys.stderr)
        return 3

    if blocked:
        print(
            f"{BLOCK_MARKER}: "
            + ", ".join(blocked)
            + " changed from LABO-family/missing to JOUABLE. Automated CI must stay red; only a human repository decision may override this gate.",
            file=sys.stderr,
        )
        return 2

    print(f"{OK_MARKER}: no automated LABO-family -> JOUABLE transition")
    return 0


def _catalog(*pairs: tuple[str, str], schema: str = SCHEMA_V1) -> dict[str, Any]:
    return {
        "schema": schema,
        "zones": [{"id": zone_id, "quality": quality} for zone_id, quality in pairs],
    }


def self_test() -> int:
    cases = [
        ("steady-labo", _catalog(("bourse", "LABO")), _catalog(("bourse", "LABO")), []),
        ("steady-jouable", _catalog(("midi", "JOUABLE")), _catalog(("midi", "JOUABLE")), []),
        ("promotion", _catalog(("bourse", "LABO")), _catalog(("bourse", "JOUABLE")), ["bourse"]),
        ("new-jouable", _catalog(), _catalog(("ixelles", "JOUABLE")), ["ixelles"]),
        ("downgrade", _catalog(("midi", "JOUABLE")), _catalog(("midi", "LABO")), []),
        ("v1-to-v2", _catalog(("bourse", "LABO")), _catalog(("bourse", "LABO"), schema=SCHEMA_V2), []),
        ("brut-steady", _catalog(("bourse", "LABO_BRUT"), schema=SCHEMA_V2), _catalog(("bourse", "LABO_BRUT"), schema=SCHEMA_V2), []),
        ("brut-promotion", _catalog(("bourse", "LABO_BRUT"), schema=SCHEMA_V2), _catalog(("bourse", "JOUABLE"), schema=SCHEMA_V2), ["bourse"]),
    ]
    for name, base, head, expected in cases:
        actual = blocked_promotions(base, head)
        if actual != expected:
            print(f"SELF_TEST_FAIL {name}: expected={expected} actual={actual}", file=sys.stderr)
            return 1
    print("HUMAN_PROMOTION_GATE_SELF_TEST_OK: fail_closed=true cases=8 schemas=v1,v2")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path)
    parser.add_argument("--head", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.base is None or args.head is None:
        parser.error("--base and --head are required unless --self-test is used")
    return validate(args.base, args.head)


if __name__ == "__main__":
    raise SystemExit(main())
