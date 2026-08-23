#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = root / "source"
    maturity = root / "maturity"
    target = root / "target.json"
    out = root / "out"

    incomplete = "bxl-e146000-n175500-s500"
    legacy = "bxl-e149000-n169000-s500"

    # Production regional source: buildings exist but four canonical base-city
    # layers are absent. This must be repair work, never DATA_READY.
    write_json(
        source / incomplete / "manifest.json",
        {
            "format": "grand-bruxelles-urbis-source-cell-v1",
            "cell_id": incomplete,
            "crs": "EPSG:31370",
            "bbox": [146000, 175500, 146500, 176000],
            "layers": {
                "buildings": {"features": 0, "file": "raw/buildings.geojson"},
            },
        },
    )
    write_json(source / incomplete / "raw" / "buildings.geojson", {"type": "FeatureCollection", "features": []})

    # Real legacy built-cell caches include embedded runtime metadata. They are not
    # accepted by the canonical runtime candidate compiler and must be rematerialized
    # into the source-cell-v1 contract instead of repeatedly consuming runtime slots.
    write_json(
        source / legacy / "manifest.json",
        {
            "format": "grand-bruxelles-urbis-built-cell-v1",
            "cell_id": legacy,
            "crs": "EPSG:31370",
            "bbox": [149000, 169000, 149500, 169500],
            "layers": {
                name: {"features": 0, "file": f"raw/{name}.geojson"}
                for name in ("buildings", "street_surfaces", "street_axes", "tram_network", "train_network")
            },
            "runtime": {"geometry_file": "runtime/cell.game.json"},
        },
    )
    for name in ("buildings", "street_surfaces", "street_axes", "tram_network", "train_network"):
        write_json(source / legacy / "raw" / f"{name}.geojson", {"type": "FeatureCollection", "features": []})

    for cell in (incomplete, legacy):
        state, blockers = mod.classify_cell(cell, source, maturity)
        assert state == "MISSING_SOURCE", (cell, state, blockers)
        assert blockers and all(item.startswith("missing_authoritative_source_file:") for item in blockers), blockers

    incomplete_state, incomplete_blockers = mod.classify_cell(incomplete, source, maturity)
    assert "missing_authoritative_source_file:street_surfaces:raw/street_surfaces.geojson" in incomplete_blockers
    assert "missing_authoritative_source_file:street_axes:raw/street_axes.geojson" in incomplete_blockers
    assert "missing_authoritative_source_file:tram_network:raw/tram_network.geojson" in incomplete_blockers
    assert "missing_authoritative_source_file:train_network:raw/train_network.geojson" in incomplete_blockers

    legacy_state, legacy_blockers = mod.classify_cell(legacy, source, maturity)
    assert legacy_state == "MISSING_SOURCE"
    assert (
        "missing_authoritative_source_file:manifest:legacy_format:grand-bruxelles-urbis-built-cell-v1"
        in legacy_blockers
    ), legacy_blockers

    write_json(
        target,
        {
            "format": mod.TARGET_FORMAT,
            "crs": "EPSG:31370",
            "cells": [
                {"cell_id": incomplete, "bbox": [146000, 175500, 146500, 176000], "municipalities": ["jette"]},
                {"cell_id": legacy, "bbox": [149000, 169000, 149500, 169500], "municipalities": ["elsene"]},
            ],
        },
    )

    report = mod.run(source, maturity, None, out, 2, target)
    rows = {row["cell_id"]: row for row in report["cells"]}
    assert rows[incomplete]["state"] == "MISSING_SOURCE"
    assert rows[incomplete]["next_action"] == "materialize_authoritative_source"
    assert rows[legacy]["state"] == "MISSING_SOURCE"
    assert rows[legacy]["next_action"] == "materialize_authoritative_source"
    assert set(report["selected_batch"]) == {incomplete, legacy}, report["selected_batch"]

print("AUTONOMOUS_CITYGEN_REGIONAL_SOURCE_CONTRACT_OK required_layers=5 legacy_upgrade=true repair_action=true fail_closed=true")
