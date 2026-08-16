#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("elevation_requirements", HERE / "build_cell_elevation_requirements.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell = root / "bxl-e149500-n169500-s500"
    source = {"cell_id": cell.name, "crs": "EPSG:31370", "bbox": [149500,169500,150000,170000], "layers": {"buildings": {"features": 1}}}
    maturity = {"cell_id": cell.name, "crs": "EPSG:31370", "bbox": source["bbox"], "maturity": {"gates": {"terrain": False, "heights": False}}}
    write(cell / "manifest.json", source)
    write(cell / "maturity.json", maturity)

    result = mod.build(cell)
    assert result["format"] == "grand-bruxelles-cell-elevation-requirements-v1"
    assert result["expected_1km_tile_codes"] == ["149169"]
    assert result["official_sources"]["dsm"]["dataset_id"] == mod.DSM_DATASET_ID
    assert result["official_sources"]["dtm"]["dataset_id"] == mod.DTM_DATASET_ID
    assert result["source_basis"]["maturity_sidecar_present"] is True
    assert result["maturity_effect"] == {"terrain_gate": False, "heights_gate": False, "reason": "requirements_only_no_raster_evidence_yet"}
    assert result["requirements_digest"] == mod._digest({k:v for k,v in result.items() if k != "requirements_digest"})

    # Regression from Autonomous CityGen pass 53: a source cell can have a valid
    # authoritative EPSG:31370 manifest before maturity.json exists. Elevation
    # requirements are only a tile plan, so the manifest bbox is sufficient and
    # must not be retried forever as an exception. Runtime gates remain false.
    manifest_only = root / "bxl-e149000-n169500-s500"
    source3 = {"cell_id": manifest_only.name, "crs": "EPSG:31370", "bbox": [149000,169500,149500,170000], "layers": {}}
    write(manifest_only / "manifest.json", source3)
    pending = mod.build(manifest_only)
    assert pending["expected_1km_tile_codes"] == ["149169"]
    assert pending["source_basis"]["maturity_sidecar_present"] is False
    assert pending["maturity_effect"]["terrain_gate"] is False
    assert pending["maturity_effect"]["heights_gate"] is False

    # A 500 m cell crossing a kilometre boundary requires both tiles exactly.
    crossing = root / "bxl-e149750-n169000-s500"
    source2 = {"cell_id": crossing.name, "crs": "EPSG:31370", "bbox": [149750,169000,150250,169500], "layers": {"buildings": {"features": 1}}}
    maturity2 = {"cell_id": crossing.name, "crs": "EPSG:31370", "bbox": source2["bbox"]}
    write(crossing / "manifest.json", source2); write(crossing / "maturity.json", maturity2)
    assert mod.build(crossing)["expected_1km_tile_codes"] == ["149169", "150169"]

    # Degree-like coordinates and source/maturity disagreement fail closed.
    bad = root / "bxl-bad"
    write(bad / "manifest.json", {"cell_id": bad.name, "crs": "EPSG:31370", "bbox": [4.3,50.8,4.4,50.9]})
    write(bad / "maturity.json", {"cell_id": bad.name, "crs": "EPSG:31370", "bbox": [4.3,50.8,4.4,50.9]})
    try:
        mod.build(bad)
    except ValueError as exc:
        assert "EPSG:31370" in str(exc)
    else:
        raise AssertionError("degree-like bbox must fail closed")

print("CELL_ELEVATION_REQUIREMENTS_GUARDRAILS_OK tile_plan=true manifest_only=true gates_false=true fail_closed=true")
