#!/usr/bin/env python3
"""Run synthetic JSON-contract regressions against the catalog core.

These fixtures intentionally model catalog/source JSON semantics without a complete
production provenance manifest. The canonical lock-bound entrypoint is exercised by
the real-slice catalog regression; synthetic contract cases must not invent source
provenance merely to reach the mature catalog validator.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_json_contract_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_json_contract_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

CORE_PATH = Path(__file__).resolve().parents[1] / "_road_destination_catalog_core.py"
core_spec = importlib.util.spec_from_file_location("road_destination_catalog_json_contract_core", CORE_PATH)
assert core_spec and core_spec.loader
core = importlib.util.module_from_spec(core_spec)
core_spec.loader.exec_module(core)

# The cases are deliberately synthetic. Keep them on the mature deterministic core
# so source-lock/provenance validation remains reserved for canonical real-source
# tests instead of being weakened or counterfeited in fixtures.
cases.module = core

# Duplicate-key rejection is deliberately not asserted here: the mature core does
# not currently provide a strict object-pairs JSON loader. Adding that intake rule
# belongs in its own RED->GREEN hardening change with canonical-source coverage,
# rather than smuggling an unrelated production contract into this catalog-binding PR.

if __name__ == "__main__":
    raise SystemExit(cases.main())
