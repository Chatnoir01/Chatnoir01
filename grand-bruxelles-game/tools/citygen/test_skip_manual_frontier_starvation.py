#!/usr/bin/env python3
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

complete = {
    "cell_id": "bxl-e149000-n169000-s500",
    "state": "DATA_READY",
    "attempts": 0,
    "evidence_progress": len(mod.EVIDENCE_STAGES),
    "next_action": "secondary_height_validation_and_terrain_runtime_checks",
}
terrain_pending = {
    "cell_id": "bxl-e149500-n169000-s500",
    "state": "DATA_READY",
    "attempts": 0,
    "evidence_progress": len(mod.EVIDENCE_STAGES) - 1,
    "next_action": "evaluate_terrain_lod",
}
height_pending = {
    "cell_id": "bxl-e150000-n169000-s500",
    "state": "DATA_READY",
    "attempts": 0,
    "evidence_progress": len(mod.EVIDENCE_STAGES) - 2,
    "next_action": "derive_building_height_candidates",
}

selected = mod.select_batch([complete, terrain_pending, height_pending], 2)
assert selected == [terrain_pending["cell_id"], height_pending["cell_id"]], selected
assert mod.select_batch([complete], 4) == []

print("CITYGEN_MANUAL_FRONTIER_STARVATION_GUARD_OK completed_frontier_skipped=true pending_cells_advance=true")
