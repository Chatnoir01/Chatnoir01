#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("candidate_package", HERE / "build_cell_candidate_package.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def feature(bid: str, x: float) -> dict:
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[[x, 169000.0], [x + 10, 169000.0], [x + 10, 169010.0], [x, 169010.0], [x, 169000.0]]]},
        "properties": {"INSPIRE_ID": bid, "BLOCK_ID": "block-1", "AREA": 100},
    }


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    cell = root / "bxl-e149000-n169000-s500"
    write_json(cell / "manifest.json", {"cell_id": cell.name, "source": "UrbIS"})
    # Deliberately reverse feature order: package must sort by building identity.
    write_json(cell / "raw" / "buildings.geojson", {"type": "FeatureCollection", "features": [feature("building-b", 149020), feature("building-a", 149000)]})

    pending = mod.build(cell, None)
    assert pending["state"] == "EVIDENCE_PENDING"
    assert pending["blockers"] == ["maturity_manifest_missing"]
    assert [row["building_id"] for row in pending["buildings"]] == ["building-a", "building-b"]
    assert pending["summary"]["valid_buildings"] == 2
    assert pending["summary"]["runtime_approved_buildings"] == 0
    assert all(row["height_m"] is None and row["runtime_approved"] is False for row in pending["buildings"])

    maturity = root / "maturity.json"
    gates = {name: True for name in mod.REQUIRED_GATES}
    write_json(maturity, {"cell_id": cell.name, "crs": "EPSG:31370", "geometry": {"authoritative_geometry_ready": True}, "maturity": {"gates": gates}})
    complete = mod.build(cell, maturity)
    assert complete["state"] == "RUNTIME_GATE_COMPLETE"
    # Even a complete cell package does not self-promote buildings into runtime.
    assert complete["summary"]["runtime_approved_buildings"] == 0
    assert all(row["runtime_approved"] is False for row in complete["buildings"])

    # Wrong CRS must fail closed.
    write_json(maturity, {"cell_id": cell.name, "crs": "EPSG:4326", "geometry": {"authoritative_geometry_ready": True}, "maturity": {"gates": gates}})
    bad_crs = mod.build(cell, maturity)
    assert bad_crs["state"] == "QUARANTINE"
    assert "maturity_crs_mismatch" in bad_crs["blockers"]

    # Invalid geometry anywhere makes the package quarantine instead of silently dropping it.
    source = json.loads((cell / "raw" / "buildings.geojson").read_text())
    source["features"].append({"type": "Feature", "geometry": {"type": "Point", "coordinates": [0, 0]}, "properties": {"INSPIRE_ID": "bad"}})
    write_json(cell / "raw" / "buildings.geojson", source)
    invalid = mod.build(cell, None)
    assert invalid["state"] == "QUARANTINE"
    assert invalid["summary"]["invalid_features"] == 1

print("CELL_CANDIDATE_PACKAGE_GUARDRAILS_OK deterministic=true epsg31370=true fail_closed=true runtime_promotion=false")
