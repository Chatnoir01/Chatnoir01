#!/usr/bin/env python3
"""Run source-path regressions against the mature deterministic catalog core.

These fixtures intentionally model only catalog source-path semantics.  They do
not fabricate provenance/source-lock evidence; the real locked slice is covered
separately through the canonical lock-bound entrypoint.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_source_path_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_source_path_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

# Keep this synthetic contract test scoped to path canonicalization.  The public
# builder is deliberately source-lock-bound now, so feeding it invented partial
# lock metadata would test provenance rather than the path contract.  Use the
# mature core builder here, and keep production/source-lock validation untouched.
cases.module.build_catalog = cases.module._core_build_catalog
cases.module._core.build_catalog = cases.module._core_build_catalog

if __name__ == "__main__":
    cases.test_catalog_source_paths_fail_closed()
    print("ROAD_DESTINATION_CATALOG_SOURCE_PATH_TEST_OK")
