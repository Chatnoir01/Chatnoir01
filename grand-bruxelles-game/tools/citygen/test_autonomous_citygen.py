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

    cells = [
        "bxl-e149000-n169000-s500",
        "bxl-e149000-n169500-s500",
        "bxl-e149500-n169000-s500",
        "bxl-e149500-n169500-s500",
    ]
    for cell in cells:
        write_json(source / cell / "manifest.json", {"cell_id": cell, "layers": ["buildings"]})

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

    report1 = mod.run(source, maturity, None, out1, 2)
    assert report1["source_cell_count"] == 4
    assert report1["counts"] == {"DATA_READY": 1, "DISCOVERED": 1, "QUARANTINE": 1, "RUNTIME_READY": 1}
    assert report1["selected_batch"] == [cells[3], cells[1]], report1["selected_batch"]
    assert cells[0] not in report1["selected_batch"]
    assert cells[2] not in report1["selected_batch"]

    state_path = out1 / "autonomous_citygen_state.json"
    report2 = mod.run(source, maturity, state_path, out2, 2)
    assert report2["run_number"] == 2
    attempts = {cell["cell_id"]: cell["attempts"] for cell in report2["cells"]}
    assert attempts[cells[3]] == 2
    assert attempts[cells[1]] == 2
    assert attempts[cells[0]] == 0
    assert attempts[cells[2]] == 0

    # Deterministic ordering is independent of filesystem creation order.
    assert mod.discover_cells(source) == sorted(cells)

print("AUTONOMOUS_CITYGEN_GUARDRAILS_OK cells=4 deterministic=true fail_closed=true resume=true")
