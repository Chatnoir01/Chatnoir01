#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("regional_runtime_frontier", HERE / "build_regional_runtime_candidates.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def production_manifest(cell_id: str, layer_names: tuple[str, ...]) -> dict:
    return {
        "format": mod.SOURCE_FORMAT,
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "layers": {
            name: {"features": 0, "file": f"raw/{name}.geojson"}
            for name in layer_names
        },
    }


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source_root = root / "sources"
    bad = "bxl-e146000-n175500-s500"
    good = "bxl-e146500-n175500-s500"

    write_json(source_root / bad / "manifest.json", production_manifest(bad, ("buildings",)))
    write_json(source_root / bad / "raw" / "buildings.geojson", {"type": "FeatureCollection", "features": []})

    bad_reasons = mod._runtime_source_repair_reasons(source_root / bad)
    assert bad_reasons == [
        "missing_layer:street_surfaces",
        "missing_layer:street_axes",
        "missing_layer:tram_network",
        "missing_layer:train_network",
    ], bad_reasons

    write_json(source_root / good / "manifest.json", production_manifest(good, mod.REQUIRED_SOURCE_LAYERS))
    for name in mod.REQUIRED_SOURCE_LAYERS:
        write_json(source_root / good / "raw" / f"{name}.geojson", {"type": "FeatureCollection", "features": []})
    assert mod._runtime_source_repair_reasons(source_root / good) == []

    state_path = root / "state.json"
    grid_path = root / "grid.json"
    write_json(
        state_path,
        {
            "format": mod.STATE_FORMAT,
            "cells": {
                bad: {"state": "DATA_READY", "evidence_progress": 10, "attempts": 0},
                good: {"state": "DATA_READY", "evidence_progress": 10, "attempts": 0},
            },
        },
    )
    write_json(
        grid_path,
        {
            "format": mod.GRID_FORMAT,
            "crs": "EPSG:31370",
            "cells": [
                {"cell_id": bad, "bbox": [146000, 175500, 146500, 176000], "municipalities": ["jette"]},
                {"cell_id": good, "bbox": [146500, 175500, 147000, 176000], "municipalities": ["jette"]},
            ],
        },
    )

    candidates, repairs = mod._eligible_rows(source_root, state_path, grid_path)
    assert [row["cell_id"] for row in candidates] == [good], candidates
    assert len(repairs) == 1 and repairs[0]["cell_id"] == bad, repairs
    assert repairs[0]["next_action"] == "rematerialize_authoritative_base_city_source"
    assert "missing_layer:street_surfaces" in repairs[0]["reasons"]

print("RUNTIME_FRONTIER_SOURCE_COMPLETENESS_OK required_layers=5 incomplete_skipped=true repair_reported=true promotion_bypass=false")
