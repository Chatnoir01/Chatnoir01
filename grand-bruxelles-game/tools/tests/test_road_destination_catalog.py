#!/usr/bin/env python3
"""Run catalog regressions while keeping lock-bound integration explicit."""
from __future__ import annotations

import importlib.util
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

# Synthetic catalog cases exercise catalog semantics with deliberately minimal
# grand-bruxelles-osm-v1 fixtures. They are not source-intake integration tests:
# the source-lock validator requires the full shipped provenance/accounting
# contract. Keep those unit cases on the mature core implementation, then restore
# the canonical lock-bound entrypoint for the real shipped-slice integration case.
CORE_PATH = cases.ROOT / "tools" / "_road_destination_catalog_core.py"
core_spec = importlib.util.spec_from_file_location("road_destination_catalog_core_test", CORE_PATH)
assert core_spec and core_spec.loader
core = importlib.util.module_from_spec(core_spec)
core_spec.loader.exec_module(core)
canonical_module = cases.module


def run_case(name: str, test) -> None:
    """Emit durable CI breadcrumbs even when GitHub does not retain job stdout."""
    print(f"ROAD_DESTINATION_CATALOG_CASE_START: {name}", flush=True)
    test()
    print(f"ROAD_DESTINATION_CATALOG_CASE_OK: {name}", flush=True)


def main() -> int:
    synthetic_tests = [
        (name, getattr(cases, name))
        for name in sorted(dir(cases))
        if name.startswith("test_")
        and name != "test_real_slice_contains_shipped_direct_entry_roads"
        and callable(getattr(cases, name))
    ]
    if not synthetic_tests:
        raise AssertionError("no synthetic road destination catalog tests discovered")

    cases.module = core
    try:
        for name, test in synthetic_tests:
            run_case(name, test)
    finally:
        cases.module = canonical_module

    run_case(
        "test_real_slice_contains_shipped_direct_entry_roads",
        cases.test_real_slice_contains_shipped_direct_entry_roads,
    )
    print(f"ROAD_DESTINATION_CATALOG_TESTS_GREEN: tests={len(synthetic_tests) + 1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
