import importlib.util
from pathlib import Path

import numpy as np
import pytest

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


def test_missing_crs_is_attached_without_changing_pixels_or_transform(tmp_path):
    import rasterio
    from rasterio.transform import from_origin

    path = tmp_path / "locked-source-no-crs.tif"
    values = np.array([[51.25, 51.5], [50.75, 51.0]], dtype=np.float32)
    transform = from_origin(149000.0, 170000.0, 0.5, 0.5)
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        width=2,
        height=2,
        count=1,
        dtype="float32",
        transform=transform,
        nodata=-3.4028234663852886e38,
    ) as dst:
        dst.write(values, 1)

    ds, owner, crs_origin = mod.open_locked_source(path)
    try:
        assert str(ds.crs) == mod.EXPECTED_CRS
        assert ds.transform == transform
        assert np.array_equal(ds.read(1), values)
        assert crs_origin == "assumed_from_locked_urbis_dtm_contract"
    finally:
        ds.close()
        if owner is not None:
            owner.close()


def test_nonmatching_embedded_crs_is_rejected(tmp_path):
    import rasterio
    from rasterio.transform import from_origin

    path = tmp_path / "wrong-crs.tif"
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        width=1,
        height=1,
        count=1,
        dtype="float32",
        transform=from_origin(149000.0, 170000.0, 0.5, 0.5),
        crs="EPSG:4326",
    ) as dst:
        dst.write(np.array([[1.0]], dtype=np.float32), 1)

    with pytest.raises(ValueError, match="Unexpected CRS"):
        mod.open_locked_source(path)
