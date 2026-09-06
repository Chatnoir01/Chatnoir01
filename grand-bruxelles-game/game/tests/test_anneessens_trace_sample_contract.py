#!/usr/bin/env python3
"""Regression coverage for frozen Anneessens visual trace sample identity/order."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("validate_anneessens_trace_samples.py")
spec = importlib.util.spec_from_file_location("anneessens_trace_validator", MODULE_PATH)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

VALID = "\n".join(
    [
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(760,360) hit=true collider_name=Building_1",
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(900,360) hit=false",
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(1100,360) hit=false",
    ]
) + "\n"

trace_count, building_hits = module.validate(VALID)
assert trace_count == 3
assert building_hits == 1

for forged in (
    VALID.replace("sample=(900,360)", "sample=(760,360)"),
    VALID.replace("sample=(900,360)", "sample=(901,360)"),
    "\n".join(reversed(VALID.strip().splitlines())) + "\n",
    VALID.replace("sample=(900,360) hit=false", "sample=(900,360) maybe=false"),
):
    try:
        module.validate(forged)
    except AssertionError:
        pass
    else:
        raise AssertionError(f"forged Anneessens trace package was accepted: {forged!r}")

print("ANNEESSENS_TRACE_SAMPLE_CONTRACT_REGRESSION_GREEN")
