#!/usr/bin/env python3
"""Lock-bound entrypoint for the deterministic Grand Bruxelles road catalog.

The validated source manifest is authoritative for catalog selection. Recursive
source discovery remains confined to the source-lock validator so unexpected
compatible documents fail closed before catalog construction.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any


def _load_sibling(module_name: str, filename: str) -> ModuleType:
    path = Path(__file__).resolve().with_name(filename)
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_core = _load_sibling("road_destination_catalog_core", "_road_destination_catalog_core.py")
_source_lock = _load_sibling("road_destination_source_lock", "validate_road_destination_source_lock.py")

# Preserve the mature catalog implementation unchanged while making its source
# selector lock-bound at this canonical entrypoint.
for _name in dir(_core):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_core, _name)

_core_build_catalog = _core.build_catalog


def _locked_documents(source_root: Path) -> list[Path]:
    source_root = source_root.resolve()
    locked: dict[str, str] = _source_lock.validate(source_root)
    repo_root = _source_lock.repository_root(source_root)
    documents = [(repo_root / relative).resolve() for relative in locked]
    for document in documents:
        try:
            document.relative_to(source_root)
        except ValueError as exc:
            raise SystemExit(
                f"ROAD_DESTINATION_SOURCE_LOCK_FAIL: locked source escapes source root {document}"
            ) from exc
    return documents


def build_catalog(source_root: Path) -> dict[str, Any]:
    """Build only from the exact validated allowlist; never from mutable discovery."""
    source_root = Path(source_root).resolve()
    documents = _locked_documents(source_root)
    original_discover = _core.discover_documents
    try:
        _core.discover_documents = lambda _source_root: list(documents)
        return _core_build_catalog(source_root)
    finally:
        _core.discover_documents = original_discover


# Core source-binding validation resolves its global build_catalog dynamically.
# Point it at the lock-bound implementation so every re-derivation is equally strict.
_core.build_catalog = build_catalog
validate_source_binding = _core.validate_source_binding


def main() -> int:
    return _core.main()


if __name__ == "__main__":
    raise SystemExit(main())
