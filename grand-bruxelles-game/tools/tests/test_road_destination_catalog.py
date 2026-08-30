#!/usr/bin/env python3
"""Run the catalog regression cases with explicit deterministic synthetic locks."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

_original_write_document = cases.write_document


def _refresh_lock(source_root: Path) -> None:
    repo_root = source_root.parent.parent
    documents = {
        path.relative_to(repo_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(source_root.rglob("*.game.json"))
        if path.is_file()
    }
    cases.write_lock(source_root, documents)


def write_document_with_lock(path: Path, roads: list[dict]) -> None:
    _original_write_document(path, roads)
    source_root = next(
        parent for parent in path.parents
        if parent.name == "osm" and parent.parent.name == "data"
    )
    _refresh_lock(source_root)


cases.write_document = write_document_with_lock


def main() -> int:
    tests = [
        getattr(cases, name) for name in sorted(dir(cases))
        if name.startswith("test_") and callable(getattr(cases, name))
    ]
    if not tests:
        raise AssertionError("no road destination catalog tests discovered")
    for test in tests:
        test()
    print(f"ROAD_DESTINATION_CATALOG_TESTS_GREEN: tests={len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
