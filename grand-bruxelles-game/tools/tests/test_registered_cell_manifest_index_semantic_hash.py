#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools/validate_registered_cell_manifest_index.py"
REGISTRY = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_fail(fn, needle: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected failure containing {needle!r}")


def main() -> int:
    tool = load(TOOL, "registered_cell_manifest_index_validator")
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tool.validate_registry(registry)
    assert tool.semantic_sha256(registry) == registry["semantic_sha256"]

    tampered = json.loads(json.dumps(registry))
    tampered["destination_readiness"] = "TAMPERED"
    expect_fail(lambda: tool.validate_registry(tampered), "semantic sha drift")

    rebased = json.loads(json.dumps(registry))
    rebased["production_base_sha"] = "0" * 40
    tool.validate_registry(rebased)
    assert tool.semantic_sha256(rebased) == registry["semantic_sha256"]

    malformed = json.loads(json.dumps(registry))
    malformed["semantic_sha256"] = "ABC"
    expect_fail(lambda: tool.validate_registry(malformed), "semantic sha format drift")

    malformed_base = json.loads(json.dumps(registry))
    malformed_base["production_base_sha"] = "not-a-sha"
    expect_fail(lambda: tool.validate_registry(malformed_base), "production base sha format drift")

    print("REGISTERED_CELL_INDEX_SEMANTIC_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
