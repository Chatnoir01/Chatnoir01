#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "tools/build_discovered_road_cell_coverage_frontier.py"
CELLS = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"


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
    builder = load(BUILDER, "road_cell_frontier_builder_manifest_envelope")
    index = json.loads(CELLS.read_text(encoding="utf-8"))
    row = index["entries"][0]
    manifest_path = ROOT / row["manifest_path"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    hidden_readiness = json.loads(json.dumps(manifest))
    hidden_readiness["safe_spawn_ready"] = True
    expect_fail(
        lambda: builder.validate_registered_cell_manifest_identity(hidden_readiness, row),
        "registered cell manifest field set drift",
    )

    print("REGISTERED_CELL_MANIFEST_ENVELOPE_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
