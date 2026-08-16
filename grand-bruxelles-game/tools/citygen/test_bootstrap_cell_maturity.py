#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("bootstrap_cell_maturity", HERE / "bootstrap_cell_maturity.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell = root / "bxl-e149000-n169000-s500"
    feature = {
        "type": "Feature",
        "properties": {"INSPIRE_ID": "BE.TEST.1"},
        "geometry": {"type": "Polygon", "coordinates": [[[149050,169050],[149100,169050],[149100,169100],[149050,169100],[149050,169050]]]},
    }
    source = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": cell.name,
        "crs": "EPSG:31370",
        "bbox": [149000,169000,149500,169500],
        "layers": {"buildings": {"features": 1, "invalid_ownership_features": 0}},
    }
    buildings = {"type": "FeatureCollection", "features": [feature]}
    write(cell / "manifest.json", source)
    write(cell / "raw" / "buildings.geojson", buildings)

    result = mod.build(cell)
    assert result["format"] == "grand-bruxelles-cell-maturity-v1"
    assert result["cell_id"] == cell.name
    assert result["crs"] == "EPSG:31370"
    assert result["maturity"]["state"] == "data_ready"
    assert result["geometry"]["authoritative_geometry_ready"] is True
    assert result["geometry"]["building_feature_count"] == 1
    assert set(result["maturity"]["gates"]) == set(mod.GATES)
    assert all(value is False for value in result["maturity"]["gates"].values())
    assert result["terrain"]["status"] == "evidence_pending"
    assert result["heights"]["status"] == "evidence_pending"
    assert result["photo_match"]["status"] == "not_evaluated"
    assert result["performance"]["budget_pass"] is False
    assert result["maturity_digest"] == mod._digest({k: v for k, v in result.items() if k != "maturity_digest"})

    # Invalid canonical ownership must never be promoted as authoritative geometry.
    source["layers"]["buildings"]["invalid_ownership_features"] = 1
    write(cell / "manifest.json", source)
    quarantined = mod.build(cell)
    assert quarantined["maturity"]["state"] == "quarantine"
    assert quarantined["geometry"]["authoritative_geometry_ready"] is False
    assert all(value is False for value in quarantined["maturity"]["gates"].values())

    # Manifest/source disagreement fails closed instead of silently changing counts.
    source["layers"]["buildings"]["invalid_ownership_features"] = 0
    source["layers"]["buildings"]["features"] = 2
    write(cell / "manifest.json", source)
    try:
        mod.build(cell)
    except ValueError as exc:
        assert "feature count mismatch" in str(exc)
    else:
        raise AssertionError("source count mismatch must fail closed")

print("BOOTSTRAP_CELL_MATURITY_GUARDRAILS_OK deterministic=true gates_false=true quarantine=true")
