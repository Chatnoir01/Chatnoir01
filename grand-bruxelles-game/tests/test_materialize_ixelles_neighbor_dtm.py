from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

import materialize_ixelles_neighbor_dtm as m  # noqa: E402


def grid(base: float, east_slope: float = 0.01, north_slope: float = 0.02) -> np.ndarray:
    rows, cols = np.meshgrid(np.arange(251), np.arange(251), indexing="ij")
    # Runtime contracts are deliberately quantized to 1e-6 m. Mirror that here
    # so the synthetic test validates contract values rather than IEEE-754 order
    # of operations at ~1e-14 m.
    return m.rounded_grid(base + cols * east_slope + rows * north_slope)


def test_shared_reference_preserves_neighbor_relative_seams() -> None:
    seed = grid(m.EXPECTED_REFERENCE_M)
    north = grid(m.EXPECTED_REFERENCE_M + 250 * 0.02)
    east = grid(m.EXPECTED_REFERENCE_M + 250 * 0.01)
    northeast = grid(m.EXPECTED_REFERENCE_M + 250 * 0.01 + 250 * 0.02)
    grids = {
        m.SEED_ID: seed,
        "bxl-e149000-n169500-s500": north,
        "bxl-e149500-n169000-s500": east,
        "bxl-e149500-n169500-s500": northeast,
    }
    seed_payload = {"heights_row_major_m": seed.reshape(-1).tolist()}
    result = m.validate_seed_and_seams(grids, seed_payload, m.EXPECTED_REFERENCE_M)
    assert result["shared_edge_pairs"] == 1004
    assert result["max_abs_shared_edge_delta_m"] == 0.0
    assert result["max_relative_shared_edge_delta_m"] == 0.0


def test_per_cell_first_sample_zeroing_would_break_world_seam() -> None:
    seed = grid(m.EXPECTED_REFERENCE_M)
    north = grid(m.EXPECTED_REFERENCE_M + 250 * 0.02)
    seed_north_relative = seed[-1, :] - seed[0, 0]
    north_south_wrong_relative = north[0, :] - north[0, 0]
    assert float(np.max(np.abs(seed_north_relative - north_south_wrong_relative))) == pytest.approx(5.0)


def test_contract_keeps_absolute_source_and_shared_datum() -> None:
    cell = "bxl-e149500-n169000-s500"
    bbox = (149500.0, 169000.0, 150000.0, 169500.0)
    values = grid(65.0)
    datum = {
        "schema": "grand-bruxelles-ixelles-shared-vertical-datum-v1",
        "seed_cell_id": m.SEED_ID,
        "reference_absolute_m": m.EXPECTED_REFERENCE_M,
        "game_height_formula": "game_y_m = official_dtm_absolute_m - reference_absolute_m",
    }
    contract = m.build_contract(cell, bbox, values, datum)
    assert contract["cell_id"] == cell
    assert contract["sample_count"] == 63001
    assert contract["spacing_m"] == 2.0
    assert contract["shared_vertical_datum"]["reference_absolute_m"] == m.EXPECTED_REFERENCE_M
    assert contract["heights_row_major_m"][0] == 65.0
    assert contract["relative_min_m"] == pytest.approx(65.0 - m.EXPECTED_REFERENCE_M)
    assert contract["runtime_approved"] is False
    assert contract["promote_runtime"] is False
