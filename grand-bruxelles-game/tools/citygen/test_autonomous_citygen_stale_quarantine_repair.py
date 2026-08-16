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


def candidate(cell_id: str, state: str, blockers: list[str]) -> dict[str, object]:
    return {
        "format": "grand-bruxelles-cell-candidate-package-v1",
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "state": state,
        "blockers": blockers,
        "authority": {"buildings_source_present": True},
    }


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
        candidate(stale, "QUARANTINE", ["authoritative_geometry_not_ready", "invalid_building_features_present"]),
    )
    write_json(
        candidates / f"{already_present}.json",
        candidate(already_present, "QUARANTINE", ["invalid_building_features_present"]),
    )
    write_json(source / already_present / "manifest.json", {"cell_id": already_present})
    write_json(
        candidates / f"{unrelated_quarantine}.json",
        candidate(unrelated_quarantine, "QUARANTINE", ["secondary_height_validation_pending"]),
    )
    write_json(candidates / f"{fresh}.json", candidate(fresh, "EVIDENCE_PENDING", []))
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

    # Fail closed: malformed identity and wrong candidate format must never be repaired.
    bad = "bxl-e142500-n167000-s500"
    malformed = candidate(stale, "QUARANTINE", [mod.REPAIR_BLOCKER])
    write_json(candidates / f"{bad}.json", malformed)
    wrong_format = candidate("bxl-e142500-n167500-s500", "QUARANTINE", [mod.REPAIR_BLOCKER])
    wrong_format["format"] = "unexpected-candidate-format"
    write_json(candidates / "bxl-e142500-n167500-s500.json", wrong_format)
    repairs = mod.select_repairs(candidates, source, target, 4)
    assert [row["cell_id"] for row in repairs] == [stale], repairs

print("AUTONOMOUS_CITYGEN_STALE_QUARANTINE_REPAIR_OK candidate_state_contract=true")
