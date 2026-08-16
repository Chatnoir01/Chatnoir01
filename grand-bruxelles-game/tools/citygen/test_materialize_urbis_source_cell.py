#!/usr/bin/env python3
import importlib.util
import json
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
    # Returned by bbox because it touches the cell, but its centroid belongs to the east neighbour.
    neighbour = building("neighbour", [[149490,169100],[149610,169100],[149610,169200],[149490,169200],[149490,169100]])
    calls = []
    def fake_fetch(request_bbox):
        calls.append(request_bbox)
        return {"type":"FeatureCollection","features":[neighbour, keep]}

    manifest = mod.materialize(cell_id, bbox, root / cell_id, fake_fetch)
    assert calls == [bbox]
    assert manifest["cell_id"] == cell_id
    assert manifest["crs"] == "EPSG:31370"
    assert manifest["layers"]["buildings"]["features"] == 1
    assert manifest["layers"]["buildings"]["ownership_filtered"] == 1
    saved = json.loads((root / cell_id / "raw" / "buildings.geojson").read_text())
    assert [f["properties"]["INSPIRE_ID"] for f in saved["features"]] == ["keep"]
    assert saved["grand_bruxelles_source"]["cell_id"] == cell_id
    assert manifest["source_digest"] == mod.digest({k:v for k,v in manifest.items() if k != "source_digest"})

    try:
        mod.materialize(cell_id, (4.0, 50.0, 4.5, 50.5), root / "bad", fake_fetch)
    except ValueError as exc:
        assert "EPSG:31370" in str(exc)
    else:
        raise AssertionError("degree-like bbox must fail closed")

print("MATERIALIZE_URBIS_SOURCE_CELL_OK ownership=true fail_closed=true")
