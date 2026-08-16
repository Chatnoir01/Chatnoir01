#!/usr/bin/env python3
import importlib.util
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("lod", HERE / "evaluate_cell_dtm_lod.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

levels = [
    {"resolution_m": 1.0, "p95_abs_error_m": 0.05},
    {"resolution_m": 2.0, "p95_abs_error_m": 0.14},
    {"resolution_m": 4.0, "p95_abs_error_m": 0.31},
    {"resolution_m": 8.0, "p95_abs_error_m": 0.70},
]
selection = mod.select_resolution(levels, 0.15)
assert selection["selected_resolution_m"] == 2.0, selection
assert selection["runtime_approved"] is False
assert selection["selection_policy"] == "coarsest_candidate_with_p95_at_or_below_threshold"
assert selection["remaining_runtime_gates"] == ["seams", "normals", "collisions", "streaming", "performance", "photo_match"]

none = mod.select_resolution([{"resolution_m":1.0,"p95_abs_error_m":0.30}], 0.15)
assert none["selected_resolution_m"] is None
assert "no_candidate_meets_p95_threshold" in none["blockers"]

try:
    import numpy as np
    from affine import Affine
except ImportError:
    raise SystemExit("numpy/affine missing in runner")

# Smooth but non-flat 0.5m source should reconstruct increasingly worse as spacing grows.
size = 100
ys, xs = np.mgrid[0:size, 0:size]
source = 60.0 + 0.02 * xs + 0.01 * ys + 0.12 * np.sin(xs / 6.0) * np.cos(ys / 7.0)
transform = Affine(0.5, 0.0, 149000.0, 0.0, -0.5, 169050.0)
bbox = (149000.0, 169000.0, 149050.0, 169050.0)
cell = mod.evaluate_array(source.astype("float64"), transform, bbox, (1.0, 2.0, 4.0, 8.0))
assert [row["resolution_m"] for row in cell["levels"]] == [1.0,2.0,4.0,8.0]
assert all(row["paired_samples"] > 0 for row in cell["levels"])
assert cell["levels"][0]["p95_abs_error_m"] <= cell["levels"][-1]["p95_abs_error_m"]
assert cell["source_pixel_size_m"] == 0.5

result = {
    "format": mod.FORMAT,
    "cell_id": "bxl-e149000-n169000-s500",
    "crs": "EPSG:31370",
    "source_value_evidence_digest": "a"*64,
    "levels": levels,
    "selection": selection,
    "runtime_approved": False,
    "maturity_effect": {"terrain_gate": False},
}
result["evidence_digest"] = mod._digest(result)
assert result["evidence_digest"] == mod._digest({k:v for k,v in result.items() if k != "evidence_digest"})

print("CELL_DTM_LOD_GUARDRAILS_OK p95_selection=true deterministic=true runtime_approval=false")
