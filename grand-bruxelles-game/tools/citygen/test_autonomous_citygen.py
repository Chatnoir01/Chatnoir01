#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = root / "source"
    maturity = root / "maturity"
    out1 = root / "out1"
    out2 = root / "out2"
    target_grid = root / "target_grid.json"

    cells = [
        "bxl-e149000-n169000-s500",
        "bxl-e149000-n169500-s500",
        "bxl-e149500-n169000-s500",
        "bxl-e149500-n169500-s500",
        "bxl-e150000-n169000-s500",
    ]
    for cell in cells[:4]:
        write_json(source / cell / "manifest.json", {"cell_id": cell, "layers": ["buildings"]})

    write_json(target_grid, {
        "format": "grand-bruxelles-regional-target-grid-v1",
        "crs": "EPSG:31370",
        "cell_size_m": 500.0,
        "cells": [
            {"cell_id": cell, "bbox": [149000 + i * 500, 169000, 149500 + i * 500, 169500], "municipalities": ["test"]}
            for i, cell in enumerate(cells)
        ],
    })

    # One fully gated cell is terminal-ready and must never re-enter work.
    write_json(maturity / f"{cells[0]}.json", {
        "cell_id": cells[0], "crs": "EPSG:31370",
        "geometry": {"authoritative_geometry_ready": True},
        "maturity": {"gates": {name: True for name in ("runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance")}},
    })

    # One data-ready cell is eligible but lower priority than undiscovered cells.
    write_json(maturity / f"{cells[1]}.json", {
        "cell_id": cells[1], "crs": "EPSG:31370",
        "geometry": {"authoritative_geometry_ready": True},
        "maturity": {"gates": {"runtime_geometry": False}},
    })

    # One bad CRS is quarantined, never silently corrected.
    write_json(maturity / f"{cells[2]}.json", {
        "cell_id": cells[2], "crs": "EPSG:4326",
        "geometry": {"authoritative_geometry_ready": True},
        "maturity": {"gates": {}},
    })

    report1 = mod.run(source, maturity, None, out1, 2, target_grid)
    assert report1["source_cell_count"] == 4
    assert report1["target_cell_count"] == 5
    assert report1["counts"] == {"DATA_READY": 1, "DISCOVERED": 1, "MISSING_SOURCE": 1, "QUARANTINE": 1, "RUNTIME_READY": 1}
    assert report1["selected_batch"] == [cells[4], cells[3]], report1["selected_batch"]
    missing = next(cell for cell in report1["cells"] if cell["cell_id"] == cells[4])
    assert missing["state"] == "MISSING_SOURCE"
    assert missing["bbox"] == [151000, 169000, 151500, 169500]
    assert missing["blockers"] == ["authoritative_source_cell_missing"]
    assert cells[0] not in report1["selected_batch"]
    assert cells[2] not in report1["selected_batch"]

    state_path = out1 / "autonomous_citygen_state.json"
    report2 = mod.run(source, maturity, state_path, out2, 2, target_grid)
    assert report2["run_number"] == 2
    attempts = {cell["cell_id"]: cell["attempts"] for cell in report2["cells"]}
    assert attempts[cells[4]] == 2
    assert attempts[cells[3]] == 2
    assert attempts[cells[0]] == 0
    assert attempts[cells[2]] == 0

    # Deterministic ordering is independent of filesystem creation order.
    assert mod.discover_cells(source) == sorted(cells[:4])

print("AUTONOMOUS_CITYGEN_GUARDRAILS_OK target_cells=5 missing_source=1 deterministic=true fail_closed=true resume=true")
