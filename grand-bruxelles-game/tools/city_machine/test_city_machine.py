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


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def write_fc(path: Path, count: int) -> None:
    write_json(path, {"type": "FeatureCollection", "features": [{"id": i} for i in range(count)]})


def osm_pair(kind: str = "tree") -> tuple[dict, dict]:
    cache = {
        "format": "grand-bruxelles-osm-zone-environment-cache-v1",
        "source": cm.OSM_SOURCE,
        "license": cm.OSM_LICENSE,
        "bbox_wgs84": [50.86, 4.29, 50.89, 4.34],
        "counts": {"tree": int(kind == "tree"), "street_lamp": int(kind == "street_lamp"), "bollard": int(kind == "bollard")},
        "elements": [{"id": 7, "lat": 50.87, "lon": 4.31, "tags": {"natural": "tree"} if kind == "tree" else {"highway": "street_lamp"}}],
    }
    stats = {"tree": int(kind == "tree"), "street_lamp": int(kind == "street_lamp"), "bollard": int(kind == "bollard"), "total": 1}
    runtime = {
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "zone": "jette",
        "source": cm.OSM_SOURCE,
        "license": cm.OSM_LICENSE,
        "projection_crs": "EPSG:31370",
        "bbox_31370": [144900.0, 173000.0, 147700.0, 175300.0],
        "source_digest": cm.canonical_digest(cache),
        "stats": stats,
        "environment_points": [{"osm_id": 7, "kind": kind, "position": [-1000.0, -4000.0]}],
    }
    return cache, runtime


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

    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        cache, runtime = osm_pair("tree")
        write_json(root / "cache.json", cache); write_json(root / "runtime.json", runtime)
        assert cm.gate_osm_environment("jette", profile, manifest, root / "cache.json", root / "runtime.json")["status"] == "PASS"
        runtime["source_digest"] = "0" * 64
        write_json(root / "runtime.json", runtime)
        expect_gate("G5_osm_environment", lambda: cm.gate_osm_environment("jette", profile, manifest, root / "cache.json", root / "runtime.json"))

        cache, runtime = osm_pair("street_lamp")
        write_json(root / "cache.json", cache); write_json(root / "runtime.json", runtime)
        expect_gate("G5_osm_environment", lambda: cm.gate_osm_environment("jette", profile, manifest, root / "cache.json", root / "runtime.json"))

    try:
        cm.build("anneessens", dry=True)
    except cm.MachineError as exc:
        assert "not enabled" in str(exc)
    else:
        raise AssertionError("known but unsupported zone must fail closed")

    assert cm.resolve_zone(catalog, "jette")["quality"] == "LABO"
    assert {row["gate"] for row in registry["layers"] if row.get("gate")} >= {
        "G1_sources_crs", "G2_spawn_ground", "G3_buildings_streets", "G4_runtime_finish", "G5_osm_environment"
    }
    print("CITY_MACHINE_TESTS_OK g1_source=true g2_pass_fail=true g3_pass_fail=true g5_digest_tree_fail_closed=true unsupported_zone_fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
