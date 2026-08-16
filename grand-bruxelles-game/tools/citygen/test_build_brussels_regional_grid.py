#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("regional_grid", HERE / "build_brussels_regional_grid.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def feature(name, ring):
    return {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
        "features": [{"type": "Feature", "properties": {"name": name}, "geometry": {"type": "Polygon", "coordinates": [ring]}}],
    }


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    # Two municipality polygons overlap the same globally aligned 500 m square.
    a = feature("A", [[149010, 169010], [149490, 169010], [149490, 169490], [149010, 169490], [149010, 169010]])
    b = feature("B", [[149250, 169250], [149750, 169250], [149750, 169750], [149250, 169750], [149250, 169250]])
    (root / "a.geojson").write_text(json.dumps(a), encoding="utf-8")
    (root / "b.geojson").write_text(json.dumps(b), encoding="utf-8")

    grid = mod.build_regional_grid(root, 500.0)
    by_id = {cell["cell_id"]: cell for cell in grid["cells"]}
    assert grid["format"] == "grand-bruxelles-regional-target-grid-v1"
    assert grid["crs"] == "EPSG:31370"
    assert "bxl-e149000-n169000-s500" in by_id
    shared = by_id["bxl-e149000-n169000-s500"]
    assert shared["municipalities"] == ["a", "b"], shared
    assert len(by_id) == len(set(by_id)), "regional grid must deduplicate shared cells"
    assert grid["summary"]["municipality_count"] == 2
    assert grid["summary"]["cell_count"] == len(grid["cells"])
    assert grid["grid_digest"] == mod.digest({k: v for k, v in grid.items() if k != "grid_digest"})

    bad = feature("Bad", [[4.3, 50.8], [4.4, 50.8], [4.4, 50.9], [4.3, 50.9], [4.3, 50.8]])
    (root / "bad.geojson").write_text(json.dumps(bad), encoding="utf-8")
    try:
        mod.build_regional_grid(root, 500.0)
    except ValueError as exc:
        assert "EPSG:31370" in str(exc)
    else:
        raise AssertionError("degree-like coordinates must fail closed")

print("BRUSSELS_REGIONAL_GRID_OK")
