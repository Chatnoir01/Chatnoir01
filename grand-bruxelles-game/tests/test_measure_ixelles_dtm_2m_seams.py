import importlib.util
from pathlib import Path

import numpy as np

TOOL = Path(__file__).parents[1] / "tools" / "measure_ixelles_dtm_2m_seams.py"
spec = importlib.util.spec_from_file_location("measure_ixelles_dtm_2m_seams", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def test_cell_and_edge_contracts():
    assert mod.EXPECTED_CRS == "EPSG:31370"
    assert mod.SPACING_M == 2.0
    assert len(mod.CELLS) == 5
    assert len(mod.SHARED_EDGES) == 5
    assert len(mod.SOURCE_ARCHIVES) == 2
    assert set(mod.SOURCE_ARCHIVES) == {"149168", "149169"}


def test_shared_edge_comparison_is_exact_and_detects_drift():
    a = np.arange(251 * 251, dtype=np.float64).reshape(251, 251)
    b = np.zeros((251, 251), dtype=np.float64)
    b[0, :] = a[-1, :]
    assert np.array_equal(mod.edge(a, "north"), mod.edge(b, "south"))
    assert mod.hash_grid(mod.edge(a, "north")) == mod.hash_grid(mod.edge(b, "south"))
    b[0, 125] += 0.001
    delta = np.abs(mod.edge(a, "north") - mod.edge(b, "south"))
    assert int(np.count_nonzero(delta)) == 1
    assert float(np.max(delta)) > 0.0


def test_grid_hash_is_deterministic_little_endian_float64():
    grid = np.array([[1.0, 2.0], [3.0, 4.0]], dtype=np.float64)
    assert mod.hash_grid(grid) == mod.hash_grid(grid.copy())
    changed = grid.copy()
    changed[1, 1] += 1e-9
    assert mod.hash_grid(grid) != mod.hash_grid(changed)
