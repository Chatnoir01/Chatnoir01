#!/usr/bin/env python3
import importlib.util
import math
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("lod", HERE / "evaluate_cell_dtm_lod.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

levels = [
    {"resolution_m": 1.0, "p95_abs_error_m": 0.05, "canonical_edge_compatible": True},
    {"resolution_m": 2.0, "p95_abs_error_m": 0.14, "canonical_edge_compatible": True},
    {"resolution_m": 4.0, "p95_abs_error_m": 0.31, "canonical_edge_compatible": True},
    {"resolution_m": 8.0, "p95_abs_error_m": 0.70, "canonical_edge_compatible": False},
]
selection = mod.select_resolution(levels, 0.15)
assert selection["selected_resolution_m"] == 2.0, selection
assert selection["runtime_approved"] is False
assert selection["selection_policy"] == "coarsest_candidate_with_p95_at_or_below_threshold"
assert selection["canonical_edge_alignment_required"] is True
assert selection["remaining_runtime_gates"] == ["seams", "normals", "collisions", "streaming", "performance", "photo_match"]

none = mod.select_resolution([{"resolution_m":1.0,"p95_abs_error_m":0.30,"canonical_edge_compatible":True}], 0.15)
assert none["selected_resolution_m"] is None
assert "no_candidate_meets_p95_threshold" in none["blockers"]

edge_blocked = mod.select_resolution([
    {"resolution_m": 8.0, "p95_abs_error_m": 0.10, "canonical_edge_compatible": False},
], 0.15)
assert edge_blocked["selected_resolution_m"] is None
assert edge_blocked["blockers"] == ["no_edge_aligned_candidate_meets_p95_threshold"]
assert mod._canonical_edge_compatible((149000.0,169000.0,149500.0,169500.0), 2.0) is True
assert mod._canonical_edge_compatible((149000.0,169000.0,149500.0,169500.0), 4.0) is True
assert mod._canonical_edge_compatible((149000.0,169000.0,149500.0,169500.0), 8.0) is False

assert mod._validated_dtm_crs_is_acceptable(None, 31370, "authoritative_source_manifest") is True
assert mod._validated_dtm_crs_is_acceptable(31370, 31370, "embedded_raster") is True
assert mod._validated_dtm_crs_is_acceptable(None, 31370, "embedded_raster") is False
assert mod._validated_dtm_crs_is_acceptable(3812, 31370, "embedded_raster") is False
assert mod._validated_dtm_crs_is_acceptable(None, 3812, "authoritative_source_manifest") is False

deps_dir = None
try:
    import numpy as np
    from affine import Affine
except ImportError:
    deps_dir = Path("/tmp/grand-bruxelles-citygen-test-deps")
    deps_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "--target", str(deps_dir),
        "numpy>=1.26,<3", "affine>=2.4,<3",
    ], check=True)
    sys.path.insert(0, str(deps_dir))
    import numpy as np
    from affine import Affine
    print("CELL_DTM_LOD_TEST_DEPS_BOOTSTRAPPED target=/tmp/grand-bruxelles-citygen-test-deps numpy=true affine=true")

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
compat = {row["resolution_m"]: row["canonical_edge_compatible"] for row in cell["levels"]}
assert compat == {1.0: True, 2.0: True, 4.0: False, 8.0: False}, compat

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

child_env = os.environ.copy()
if deps_dir is not None:
    existing_pythonpath = child_env.get("PYTHONPATH", "")
    child_env["PYTHONPATH"] = str(deps_dir) if not existing_pythonpath else str(deps_dir) + os.pathsep + existing_pythonpath
subprocess.run([sys.executable, str(HERE / "test_build_cell_terrain_runtime_candidate.py")], check=True, env=child_env)

print("CELL_DTM_LOD_GUARDRAILS_OK p95_selection=true canonical_edges=true deterministic=true terrain_candidate_regression=true runtime_approval=false")
