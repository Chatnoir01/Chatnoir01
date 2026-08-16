#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("materialize", HERE / "materialize_urbis_source_cell.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def building(bid, ring):
    return {"type": "Feature", "properties": {"INSPIRE_ID": bid, "AREA": 100}, "geometry": {"type": "Polygon", "coordinates": [ring]}}


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell_id = "bxl-e149000-n169000-s500"
    bbox = (149000.0, 169000.0, 149500.0, 169500.0)
    keep = building("keep", [[149100,169100],[149200,169100],[149200,169200],[149100,169200],[149100,169100]])
    neighbour = building("neighbour", [[149490,169100],[149610,169100],[149610,169200],[149490,169200],[149490,169100]])
    calls = []
    def fake_fetch(request_bbox):
        calls.append(request_bbox)
        return {"type":"FeatureCollection","features":[neighbour, keep]}

    cell_dir = root / cell_id
    manifest = mod.materialize(cell_id, bbox, cell_dir, fake_fetch)
    assert calls == [bbox]
    assert manifest["cell_id"] == cell_id
    assert manifest["crs"] == "EPSG:31370"
    assert manifest["layers"]["buildings"]["features"] == 1
    assert manifest["layers"]["buildings"]["ownership_filtered"] == 1
    saved = json.loads((cell_dir / "raw" / "buildings.geojson").read_text())
    assert [f["properties"]["INSPIRE_ID"] for f in saved["features"]] == ["keep"]
    maturity = json.loads((cell_dir / "maturity.json").read_text())
    assert maturity["cell_id"] == cell_id
    assert maturity["geometry"]["authoritative_geometry_ready"] is True
    assert maturity["maturity"]["state"] == "data_ready"
    assert all(value is False for value in maturity["maturity"]["gates"].values())
    assert manifest["source_digest"] == mod.digest({k:v for k,v in manifest.items() if k != "source_digest"})

    try:
        mod.materialize(cell_id, (4.0, 50.0, 4.5, 50.5), root / "bad", fake_fetch)
    except ValueError as exc:
        assert "EPSG:31370" in str(exc)
    else:
        raise AssertionError("degree-like bbox must fail closed")

subprocess.run([sys.executable, str(HERE / "test_materialize_urbis_source_cell_multipolygon.py")], check=True)

print("MATERIALIZE_URBIS_SOURCE_CELL_OK ownership=true multipolygon=true maturity_sidecar=true fail_closed=true")
