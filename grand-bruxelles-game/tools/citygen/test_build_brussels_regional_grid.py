#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import urllib.error
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


def durable_grid_payload():
    payload = {
        "format": "grand-bruxelles-regional-target-grid-v1",
        "authority": "UrbIS Municipalities official geometry",
        "crs": "EPSG:31370",
        "cell_size_m": 500.0,
        "summary": {"municipality_count": 19, "cell_count": 1},
        "cells": [{
            "cell_id": "bxl-e149000-n169000-s500",
            "bbox": [149000.0, 169000.0, 149500.0, 169500.0],
            "municipalities": ["bruxelles"],
        }],
    }
    payload["grid_digest"] = mod.digest(payload)
    return payload


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
    assert shared["municipalities"] == ["a-0", "b-0"], shared
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

    # Regression: the scheduled CityGen pass already persists a validated official
    # regional grid. A transient live WFS timeout must be allowed to reuse exactly
    # that durable grid, but only after revalidating its CRS/count/digest contract.
    fallback_path = root / "durable_grid.json"
    fallback_payload = durable_grid_payload()
    fallback_path.write_text(json.dumps(fallback_payload), encoding="utf-8")
    original_fetch = mod.fetch_official
    try:
        def timeout_fetch(_output):
            raise urllib.error.URLError(TimeoutError("timed out"))
        mod.fetch_official = timeout_fetch
        recovered = mod.resolve_regional_grid(root / "network", 500.0, True, fallback_path)
        assert recovered == fallback_payload
    finally:
        mod.fetch_official = original_fetch

    tampered = dict(fallback_payload)
    tampered["grid_digest"] = "0" * 64
    fallback_path.write_text(json.dumps(tampered), encoding="utf-8")
    try:
        mod.load_fallback_grid(fallback_path, 500.0)
    except ValueError as exc:
        assert "digest" in str(exc)
    else:
        raise AssertionError("tampered durable grid must fail closed")

print("BRUSSELS_REGIONAL_GRID_OK")
