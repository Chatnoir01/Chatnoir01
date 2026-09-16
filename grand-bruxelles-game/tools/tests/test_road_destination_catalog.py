#!/usr/bin/env python3
"""Run catalog regressions while keeping lock-bound integration explicit."""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

CORE_PATH = cases.ROOT / "tools" / "_road_destination_catalog_core.py"
core_spec = importlib.util.spec_from_file_location("road_destination_catalog_core_test", CORE_PATH)
assert core_spec and core_spec.loader
core = importlib.util.module_from_spec(core_spec)
core_spec.loader.exec_module(core)
canonical_module = cases.module
REAL_CASE = "test_real_slice_contains_shipped_direct_entry_roads"
SOURCE_SET_CASE = "test_locked_source_selection_ignores_unlisted_compatible_documents"


def discovered_cases() -> list[tuple[str, object]]:
    return [
        (name, getattr(cases, name))
        for name in sorted(dir(cases))
        if name.startswith("test_") and callable(getattr(cases, name))
    ]


def run_case(name: str, test) -> None:
    print(f"ROAD_DESTINATION_CATALOG_CASE_START: {name}", flush=True)
    if name == REAL_CASE:
        cases.module = canonical_module
        test()
    else:
        cases.module = core
        original_source_validator = None
        if name == SOURCE_SET_CASE:
            # This synthetic case isolates allowlist/set-drift semantics. Its tiny
            # documents intentionally do not model the production provenance,
            # corridor and accounting contract; those are exercised by REAL_CASE.
            # Keep the production validator unchanged and bypass only payload-shape
            # validation inside this one fixture so the intended set-drift witness
            # can reach the exact gate it asserts.
            original_source_validator = cases.lock_module.validate_source_payload
            cases.lock_module.validate_source_payload = lambda _path, _payload: None
        try:
            test()
        finally:
            if original_source_validator is not None:
                cases.lock_module.validate_source_payload = original_source_validator
            cases.module = canonical_module
    print(f"ROAD_DESTINATION_CATALOG_CASE_OK: {name}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", help="run exactly one named regression case")
    args = parser.parse_args()
    available = discovered_cases()
    if not available:
        raise AssertionError("no road destination catalog tests discovered")
    if args.case:
        selected = [(name, test) for name, test in available if name == args.case]
        if not selected:
            raise SystemExit(f"unknown road destination catalog case: {args.case}")
    else:
        selected = available
    for name, test in selected:
        run_case(name, test)
    print(f"ROAD_DESTINATION_CATALOG_TESTS_GREEN: tests={len(selected)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
