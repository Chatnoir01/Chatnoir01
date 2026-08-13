import importlib.util
import sys
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
TOOL = TOOLS / "measure_ixelles_dtm_2m_normal_continuity.py"
spec = importlib.util.spec_from_file_location("measure_ixelles_dtm_2m_normal_continuity", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def test_normal_contract_scope_and_sources():
    assert mod.SPACING_M == 2.0
    assert len(mod.CELLS) == 5
    assert len(mod.SHARED_EDGES) == 5
    assert mod.SOURCE_ARCHIVES == {
        "149168": "f0277df26876c6c7cd3e00050e3d3a44b420b2df4bf4271e680717adeabb09b4",
        "149169": "c8135aa8456a5f2de8efb2e05dbf9c993ae9c97e4aa7f4d56c6c331345bac4f8",
    }


def test_shared_edge_coordinates_are_exactly_identical():
    for a_id, a_side, b_id, b_side in mod.SHARED_EDGES:
        ax, ay = mod.edge_coords(mod.CELLS[a_id], a_side)
        bx, by = mod.edge_coords(mod.CELLS[b_id], b_side)
        assert ax.size == 251
        assert ay.size == 251
        assert np.array_equal(ax, bx)
        assert np.array_equal(ay, by)


def test_plane_normals_are_exact_and_central_inside_source():
    from rasterio.transform import from_origin

    # z = 0.25*x - 0.5*y + constant on a 0.5 m raster.
    transform = from_origin(0.0, 20.0, 0.5, 0.5)
    h = w = 40
    cols = np.arange(w, dtype=np.float64) + 0.5
    rows = np.arange(h, dtype=np.float64) + 0.5
    xs = cols * 0.5
    ys = 20.0 - rows * 0.5
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    array = 0.25 * xx - 0.5 * yy + 7.0

    qx = np.array([5.0, 8.0, 11.0], dtype=np.float64)
    qy = np.array([5.0, 8.0, 11.0], dtype=np.float64)
    normals, methods = mod.normals_at(array, transform, qx, qy)
    expected = np.array([-0.25, 0.5, 1.0], dtype=np.float64)
    expected /= np.linalg.norm(expected)
    assert np.allclose(normals, expected[None, :], atol=1e-12)
    assert methods["x_central"] == 3
    assert methods["y_central"] == 3
    assert methods["x_forward"] == methods["x_backward"] == 0
    assert methods["y_forward"] == methods["y_backward"] == 0


def test_outer_boundary_uses_one_sided_source_not_invented_halo():
    from rasterio.transform import from_origin

    transform = from_origin(0.13, 10.07, 0.5, 0.5)
    array = np.arange(20 * 20, dtype=np.float64).reshape(20, 20)
    xs = np.array([0.0], dtype=np.float64)
    ys = np.array([5.0], dtype=np.float64)
    derivative, method = mod._axis_derivative(array, transform, xs, ys, "x")
    assert np.isfinite(derivative[0])
    assert method[0] == 1


def test_angular_delta_is_zero_for_bit_identical_normals_and_detects_drift():
    a = np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0]], dtype=np.float64)
    assert np.array_equal(mod.angular_deltas_deg(a, a), np.zeros(2))
    b = a.copy()
    b[1] = np.array([0.0, np.sqrt(0.5), np.sqrt(0.5)])
    d = mod.angular_deltas_deg(a, b)
    assert d[0] == 0.0
    assert d[1] > 0.0


def test_hash_float64_is_deterministic_and_sensitive():
    values = np.array([[0.0, 0.0, 1.0], [0.1, 0.2, 0.9]], dtype=np.float64)
    assert mod.hash_float64(values) == mod.hash_float64(values.copy())
    changed = values.copy()
    changed[1, 2] += 1e-12
    assert mod.hash_float64(values) != mod.hash_float64(changed)
