#!/usr/bin/env python3
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

mature = {
    "cell_id": "bxl-e141500-n167500-s500",
    "state": "DATA_READY",
    "attempts": 1,
    "evidence_progress": 7,
    "next_action": "derive_elevation_candidate_frontier",
}
new_source = {
    "cell_id": "bxl-e142000-n168000-s500",
    "state": "MISSING_SOURCE",
    "attempts": 0,
    "evidence_progress": 0,
    "next_action": "materialize_authoritative_source",
}
discovered = {
    "cell_id": "bxl-e141500-n168000-s500",
    "state": "DISCOVERED",
    "attempts": 0,
    "evidence_progress": 0,
    "next_action": "derive_elevation_requirements",
}

selected = mod.select_batch([new_source, mature, discovered], 2)
assert selected == [mature["cell_id"], discovered["cell_id"]], selected
assert mod.select_batch([new_source, mature], 1) == [mature["cell_id"]]
assert mod.select_batch([new_source], 1) == [new_source["cell_id"]]

print("CITYGEN_MATURE_FRONTIER_PRIORITY_OK mature_source_cells_finish_before_expansion=true")
