#!/usr/bin/env python3
"""Regression: declared authoritative source files must physically exist."""
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


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = root / "source"
    maturity = root / "maturity"
    target = root / "target.json"
    out = root / "out"
    broken = "bxl-e149000-n169500-s500"
    good = "bxl-e149500-n169500-s500"

    for cell in (broken, good):
        write_json(
            source / cell / "manifest.json",
            {
                "format": "grand-bruxelles-urbis-built-cell-v1",
                "cell_id": cell,
                "crs": "EPSG:31370",
                "layers": {
                    "buildings": {
                        "wfs_name": "urbisvector:Buildings",
                        "features": 418,
                        "file": "raw/buildings.geojson",
                    }
                },
            },
        )
        write_json(
            maturity / f"{cell}.json",
            {
                "cell_id": cell,
                "crs": "EPSG:31370",
                "geometry": {"authoritative_geometry_ready": True},
                "maturity": {"gates": {name: False for name in mod.MATURITY_GATES}},
            },
        )
    write_json(source / good / "raw" / "buildings.geojson", {"type": "FeatureCollection", "features": []})
    write_json(
        target,
        {
            "format": mod.TARGET_FORMAT,
            "crs": "EPSG:31370",
            "cells": [
                {"cell_id": broken, "bbox": [149000, 169500, 149500, 170000], "municipalities": ["Ixelles"]},
                {"cell_id": good, "bbox": [149500, 169500, 150000, 170000], "municipalities": ["Ixelles"]},
            ],
        },
    )

    state, blockers = mod.classify_cell(broken, source, maturity)
    assert state == "MISSING_SOURCE", (state, blockers)
    assert blockers == ["missing_authoritative_source_file:buildings:raw/buildings.geojson"], blockers

    good_state, good_blockers = mod.classify_cell(good, source, maturity)
    assert good_state == "DATA_READY", (good_state, good_blockers)

    # A physically incomplete source cell is repair work, not regional expansion.
    # It must outrank ordinary DATA_READY evidence advancement so a stale manifest
    # cannot remain indefinitely starved behind the mature-source frontier.
    report = mod.run(source, maturity, None, out, 1, target)
    broken_row = next(row for row in report["cells"] if row["cell_id"] == broken)
    assert broken_row["state"] == "MISSING_SOURCE", broken_row
    assert broken_row["evidence_progress"] == 0, broken_row
    assert broken_row["next_action"] == "materialize_authoritative_source", broken_row
    assert report["selected_batch"] == [broken], report["selected_batch"]

print("AUTONOMOUS_CITYGEN_SOURCE_COMPLETENESS_OK fail_closed=true rematerialize=true repair_priority=true")
