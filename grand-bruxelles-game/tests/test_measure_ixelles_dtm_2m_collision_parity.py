from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

from measure_ixelles_dtm_2m_collision_parity import (  # noqa: E402
    build_index_buffer,
    compare_surface_collision,
)


def _grid(rows: int = 3, cols: int = 3) -> np.ndarray:
    yy, xx = np.meshgrid(np.arange(rows), np.arange(cols), indexing="ij")
    return (50.0 + xx * 0.5 + yy * 0.25).astype(np.float64)


def test_index_buffer_is_two_consistent_triangles_per_quad() -> None:
    idx = build_index_buffer(3, 3)
    assert idx.shape == (8, 3)
    assert idx.tolist()[:2] == [[0, 3, 1], [1, 3, 4]]
    assert idx.tolist()[-2:] == [[4, 7, 5], [5, 7, 8]]


def test_collision_parity_passes_for_identical_independent_grids() -> None:
    render = _grid()
    collision = render.copy()
    result = compare_surface_collision(render, collision, west=149000.0, south=169000.0, spacing_m=2.0)
    assert result["vertex_count"] == 9
    assert result["triangle_count"] == 8
    assert result["max_abs_vertex_z_delta_m"] == 0.0
    assert result["nonzero_vertex_z_delta_count"] == 0
    assert result["render_vertex_sha256"] == result["collision_vertex_sha256"]
    assert result["render_index_sha256"] == result["collision_index_sha256"]
    assert result["collision_parity_pass"] is True


def test_collision_parity_rejects_any_height_divergence() -> None:
    render = _grid()
    collision = render.copy()
    collision[1, 1] += 0.001
    result = compare_surface_collision(render, collision, west=149000.0, south=169000.0, spacing_m=2.0)
    assert result["max_abs_vertex_z_delta_m"] == pytest.approx(0.001)
    assert result["nonzero_vertex_z_delta_count"] == 1
    assert result["collision_parity_pass"] is False


def test_collision_parity_rejects_shape_mismatch() -> None:
    with pytest.raises(ValueError, match="shape"):
        compare_surface_collision(_grid(3, 3), _grid(2, 3), west=0.0, south=0.0, spacing_m=2.0)