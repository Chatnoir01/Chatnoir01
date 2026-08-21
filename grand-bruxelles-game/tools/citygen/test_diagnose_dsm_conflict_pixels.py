#!/usr/bin/env python3
"""Regression for fail-closed DSM conflict pixel diagnostics."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("diagnose_dsm_conflict_pixels.py")
spec = importlib.util.spec_from_file_location("dsm_conflict_pixels", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Synthetic 7x7 footprint: outer ring follows the primary DSM hypothesis (12 m),
# inner 5x5 follows the semantic hypothesis (4 m). This tests spatial reporting
# only; no cause or automatic resolution may be inferred.
inside = [[True] * 7 for _ in range(7)]
deltas = [[4.0] * 7 for _ in range(7)]
for y in range(7):
    for x in range(7):
        if y in (0, 6) or x in (0, 6):
            deltas[y][x] = 12.0

result = module.analyze_grid(
    inside,
    deltas,
    primary_height_m=12.0,
    semantic_height_m=4.0,
    strong_delta_m=2.0,
    erosion_pixels=2,
)
assert result["valid_pixel_count"] == 49
assert result["bands"]["primary"]["pixel_count"] == 24
assert result["bands"]["semantic"]["pixel_count"] == 25
assert result["bands"]["other"]["pixel_count"] == 0
assert result["zones"]["edge"]["primary_band_fraction"] == 1.0
assert result["zones"]["interior"]["semantic_band_fraction"] == 1.0
assert result["bands"]["primary"]["largest_component_pixels"] == 24
assert result["bands"]["semantic"]["largest_component_pixels"] == 25
assert result["policy"]["cause_inference_allowed"] is False
assert result["policy"]["automatic_resolution_allowed"] is False
assert result["policy"]["runtime_approved"] is False
assert result["policy"]["thresholds_changed"] is False
assert result["strong_delta_m"] == 2.0
print("DSM_CONFLICT_PIXEL_AUTOPSY_TEST_OK valid=49 primary=24 semantic=25 automatic_resolution=false")
