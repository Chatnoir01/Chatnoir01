#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

import city_machine as cm


def expect_gate(name: str, fn) -> None:
    try:
        fn()
    except cm.GateError as exc:
        assert exc.gate == name, exc
    else:
        raise AssertionError(f"expected {name} failure")


def write_fc(path: Path, count: int) -> None:
    path.write_text(json.dumps({"type": "FeatureCollection", "features": [{"id": i} for i in range(count)]}), encoding="utf-8")


def main() -> int:
    registry = cm.load_registry()
    catalog = cm.read_json(cm.CATALOG)
    profile = registry["zone_profiles"]["jette"]
    zone = cm.resolve_zone(catalog, "jette")
    manifest = cm.source_contract(profile)

    g2 = cm.gate_spawn(zone, profile, manifest)
    assert g2["status"] == "PASS"
    bad_zone = dict(zone)
    bad_zone["spawn"] = [999999.0, 1.05, 999999.0]
    expect_gate("G2_spawn_ground", lambda: cm.gate_spawn(bad_zone, profile, manifest))

    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write_fc(root / "buildings.game.json", 2)
        write_fc(root / "street_surfaces.game.json", 1)
        assert cm.gate_content(profile, root)["status"] == "PASS"
        write_fc(root / "street_surfaces.game.json", 0)
        expect_gate("G3_buildings_streets", lambda: cm.gate_content(profile, root))

    try:
        cm.build("anneessens", dry=True)
    except cm.MachineError as exc:
        assert "not enabled" in str(exc)
    else:
        raise AssertionError("known but unsupported zone must fail closed")

    assert cm.resolve_zone(catalog, "jette")["quality"] == "LABO"
    assert {row["gate"] for row in registry["layers"] if row.get("gate")} >= {
        "G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets", "G4_runtime_finish"
    }
    print("CITY_MACHINE_TESTS_OK g1_source=true g2_pass_fail=true g3_pass_fail=true unsupported_zone_fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
