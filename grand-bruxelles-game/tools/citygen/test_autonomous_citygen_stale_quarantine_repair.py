#!/usr/bin/env python3
"""Regression: stale quarantine candidates must be repaired before fresh expansion."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    source = root / "source"
    maturity = root / "maturity"
    candidates = root / "candidates"
    output = root / "out"
    target = root / "target.json"
    state = root / "state.json"

    stale = "bxl-e142000-n167000-s500"
    fresh = "bxl-e150000-n170000-s500"
    ready = "bxl-e149000-n169000-s500"

    write_json(
        source / ready / "manifest.json",
        {"cell_id": ready, "crs": "EPSG:31370", "layers": ["buildings"]},
    )
    write_json(
        source / ready / "maturity.json",
        {
            "cell_id": ready,
            "crs": "EPSG:31370",
            "geometry": {"authoritative_geometry_ready": True},
            "maturity": {"gates": {name: False for name in mod.MATURITY_GATES}},
        },
    )
    for filename, _action in mod.EVIDENCE_STAGES:
        write_json(source / ready / filename, {"cell_id": ready})

    write_json(
        candidates / f"{stale}.json",
        {
            "cell_id": stale,
            "status": "QUARANTINE",
            "blockers": ["authoritative_geometry_not_ready", "invalid_building_features_present"],
            "authority": {"buildings_source_present": True},
        },
    )
    write_json(
        target,
        {
            "format": mod.TARGET_FORMAT,
            "crs": "EPSG:31370",
            "cell_size_m": 500.0,
            "cells": [
                {"cell_id": stale, "bbox": [142000, 167000, 142500, 167500], "municipalities": ["Anderlecht"]},
                {"cell_id": fresh, "bbox": [150000, 170000, 150500, 170500], "municipalities": ["test"]},
                {"cell_id": ready, "bbox": [149000, 169000, 149500, 169500], "municipalities": ["test"]},
            ],
        },
    )
    write_json(
        state,
        {
            "format": mod.FORMAT,
            "run_number": 7,
            "cells": {
                stale: {"state": "MISSING_SOURCE", "attempts": 9, "evidence_progress": 0, "next_action": "materialize_authoritative_source"},
                fresh: {"state": "MISSING_SOURCE", "attempts": 0, "evidence_progress": 0, "next_action": "materialize_authoritative_source"},
                ready: {"state": "DATA_READY", "attempts": 2, "evidence_progress": len(mod.EVIDENCE_STAGES), "next_action": mod.MANUAL_FRONTIER_ACTION},
            },
        },
    )

    report = mod.run(
        source,
        maturity,
        state,
        output,
        1,
        target,
        candidate_root=candidates,
    )
    stale_row = next(row for row in report["cells"] if row["cell_id"] == stale)
    assert stale_row["state"] == "MISSING_SOURCE"
    assert stale_row["repair_priority"] is True
    assert "stale_quarantine_candidate_requires_rematerialization" in stale_row["blockers"]
    assert report["selected_batch"] == [stale], report["selected_batch"]

print("AUTONOMOUS_CITYGEN_STALE_QUARANTINE_REPAIR_OK")
