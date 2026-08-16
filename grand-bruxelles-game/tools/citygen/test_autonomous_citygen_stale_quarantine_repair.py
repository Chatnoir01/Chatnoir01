#!/usr/bin/env python3
"""Regression: stale quarantine candidates must be repaired before fresh expansion."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("stale_repair", HERE / "select_stale_quarantine_repairs.py")
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    source = root / "source"
    candidates = root / "candidates"
    target = root / "target.json"

    stale = "bxl-e142000-n167000-s500"
    fresh = "bxl-e150000-n170000-s500"
    already_present = "bxl-e142000-n167500-s500"
    unrelated_quarantine = "bxl-e141500-n167500-s500"

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
        candidates / f"{already_present}.json",
        {
            "cell_id": already_present,
            "status": "QUARANTINE",
            "blockers": ["invalid_building_features_present"],
        },
    )
    write_json(source / already_present / "manifest.json", {"cell_id": already_present})
    write_json(
        candidates / f"{unrelated_quarantine}.json",
        {
            "cell_id": unrelated_quarantine,
            "status": "QUARANTINE",
            "blockers": ["secondary_height_validation_pending"],
        },
    )
    write_json(
        candidates / f"{fresh}.json",
        {"cell_id": fresh, "status": "READY", "blockers": []},
    )
    write_json(
        target,
        {
            "format": mod.TARGET_FORMAT,
            "crs": "EPSG:31370",
            "cell_size_m": 500.0,
            "cells": [
                {"cell_id": stale, "bbox": [142000, 167000, 142500, 167500], "municipalities": ["Anderlecht"]},
                {"cell_id": already_present, "bbox": [142000, 167500, 142500, 168000], "municipalities": ["Anderlecht"]},
                {"cell_id": unrelated_quarantine, "bbox": [141500, 167500, 142000, 168000], "municipalities": ["Anderlecht"]},
                {"cell_id": fresh, "bbox": [150000, 170000, 150500, 170500], "municipalities": ["test"]},
            ],
        },
    )

    repairs = mod.select_repairs(candidates, source, target, 4)
    assert [row["cell_id"] for row in repairs] == [stale], repairs
    assert repairs[0]["bbox"] == [142000, 167000, 142500, 167500]

    # Fail closed: malformed candidate identity must not be repaired.
    bad = "bxl-e142500-n167000-s500"
    write_json(candidates / f"{bad}.json", {"cell_id": stale, "status": "QUARANTINE", "blockers": [mod.REPAIR_BLOCKER]})
    repairs = mod.select_repairs(candidates, source, target, 4)
    assert [row["cell_id"] for row in repairs] == [stale], repairs

print("AUTONOMOUS_CITYGEN_STALE_QUARANTINE_REPAIR_OK")
