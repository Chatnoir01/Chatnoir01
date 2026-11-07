#!/usr/bin/env python3
"""Regression for read-only historical-vs-2021 conflict surface comparison."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
MODULE = HERE / "diagnose_dhmv_2021_conflict_shift.py"
spec = importlib.util.spec_from_file_location("shift", MODULE)
assert spec is not None and spec.loader is not None
shift = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shift)

inside_current = np.ones((7, 7), dtype=bool)
inside_historical = np.ones((5, 5), dtype=bool)
current = np.full((7, 7), 12.0, dtype=float)
historical = np.full((5, 5), 4.0, dtype=float)
result = shift.compare_epoch_grids(
    inside_current,
    current,
    inside_historical,
    historical,
    primary_height_m=12.0,
    semantic_height_m=4.0,
    strong_delta_m=2.0,
    current_pixel_m=0.5,
    historical_pixel_m=1.0,
)
assert result["current_2021"]["edge_erosion_pixels"] == 2
assert result["historical_2013_2015"]["edge_erosion_pixels"] == 1
assert result["edge_zone_nominal_width_m"] == 1.0
assert result["current_2021"]["grid"]["bands"]["primary"]["fraction_of_valid"] == 1.0
assert result["current_2021"]["grid"]["bands"]["semantic"]["fraction_of_valid"] == 0.0
assert result["historical_2013_2015"]["grid"]["bands"]["semantic"]["fraction_of_valid"] == 1.0
assert result["historical_2013_2015"]["grid"]["bands"]["primary"]["fraction_of_valid"] == 0.0
assert result["differences"]["p50_shift_2021_minus_historical_m"] == 8.0
assert result["policy"]["physical_change_inference_allowed"] is False
assert result["policy"]["source_winner_inference_allowed"] is False
assert result["policy"]["automatic_resolution_allowed"] is False
assert result["policy"]["runtime_approved"] is False
assert result["policy"]["thresholds_changed"] is False

try:
    shift.compare_epoch_grids(
        inside_current,
        current,
        inside_historical,
        historical,
        primary_height_m=12.0,
        semantic_height_m=4.0,
        strong_delta_m=2.01,
    )
except ValueError as exc:
    assert "threshold changed" in str(exc)
else:
    raise AssertionError("changed strong threshold must fail closed")

print("DHMV_2021_CONFLICT_SHIFT_TEST_OK")
