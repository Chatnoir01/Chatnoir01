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
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    sources = root / "sources"
    existing = root / "existing"
    output = root / "output"
    state_path = root / "state.json"
    grid_path = root / "grid.json"
    report_path = root / "report.json"

    cells = {}
    grid_cells = []

    # Hostile distribution: forty mature cells in one municipality would dominate
    # a simple priority sort, while the other 18 municipalities have one candidate.
    for index in range(40):
        cell_id = f"bxl-e{140000 + index * 500}-n160000-s500"
        cells[cell_id] = {
            "state": "DATA_READY",
            "evidence_progress": 10,
            "attempts": 0,
            "next_action": "secondary_height_validation_and_terrain_runtime_checks",
        }
        grid_cells.append({"cell_id": cell_id, "bbox": [140000 + index * 500, 160000, 140500 + index * 500, 160500], "municipalities": ["Commune 00"]})
        write_json(sources / cell_id / "manifest.json", {"cell_id": cell_id})

    for index in range(1, 19):
        cell_id = f"bxl-e160000-n{160000 + index * 500}-s500"
        cells[cell_id] = {
            "state": "DATA_READY",
            "evidence_progress": 1,
            "attempts": 3,
            "next_action": "secondary_height_validation_and_terrain_runtime_checks",
        }
        grid_cells.append({"cell_id": cell_id, "bbox": [160000, 160000 + index * 500, 160500, 160500 + index * 500], "municipalities": [f"Commune {index:02d}"]})
        write_json(sources / cell_id / "manifest.json", {"cell_id": cell_id})

    missing_id = "bxl-e170000-n170000-s500"
    cells[missing_id] = {"state": "MISSING_SOURCE", "evidence_progress": 0, "attempts": 0}
    grid_cells.append({"cell_id": missing_id, "bbox": [170000, 170000, 170500, 170500], "municipalities": ["Commune 18"]})

    write_json(state_path, {"format": mod.STATE_FORMAT, "run_number": 1, "cells": cells})
    write_json(grid_path, {"format": mod.GRID_FORMAT, "crs": "EPSG:31370", "cells": grid_cells})

    already = sorted(cells)[0]
    write_json(existing / already / "candidate.json", {"format": mod.CANDIDATE_FORMAT, "cell_id": already})

    discovered = mod.discover_candidates(sources, state_path, grid_path, existing)
    assert already not in {row["cell_id"] for row in discovered}
    assert missing_id not in {row["cell_id"] for row in discovered}

    selected = mod.select_batch(discovered, 32)
    municipalities = {name for row in selected for name in row["municipalities"]}
    assert len(selected) == 32
    assert municipalities == {f"Commune {index:02d}" for index in range(19)}, municipalities

    small = mod.select_batch(discovered, 4)
    assert len(small) == 4
    assert all(row["municipalities"] == ["Commune 00"] for row in small), small

    def fake_build(cell_dir: Path, out_dir: Path):
        out_dir.mkdir(parents=True, exist_ok=True)
        candidate = {
            "format": mod.CANDIDATE_FORMAT,
            "cell_id": cell_dir.name,
            "candidate_digest": f"digest:{cell_dir.name}",
            "stats": {"buildings": 1, "street_surfaces": 1},
            "safety": {
                "runtime_mount_authorized": False,
                "jouable_promotion_authorized": False,
            },
        }
        write_json(out_dir / "candidate.json", candidate)
        return candidate

    original_build = mod.runtime_bundle.build
    mod.runtime_bundle.build = fake_build
    try:
        report = mod.run(sources, state_path, grid_path, output, report_path, 32, existing)
    finally:
        mod.runtime_bundle.build = original_build

    assert report["selected_count"] == 32
    assert report["built_count"] == 32
    assert report["built_municipality_count"] == 19
    assert report["failure_count"] == 0
    assert report["runtime_mount_authorized"] is False
    assert report["jouable_promotion_authorized"] is False
    assert report["next_gate"] == "validate_runtime_candidate_then_attach_maturity_evidence_before_promotion"

print("REGIONAL_RUNTIME_CANDIDATE_FRONTIER_TEST_OK batch=32 municipalities=19 skip_existing=true candidate_only=true promotion_bypass=false")
