#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "tools/build_discovered_road_cell_coverage_frontier.py"
VALIDATOR = ROOT / "tools/validate_discovered_road_cell_coverage_source_binding.py"
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
FRAME = ROOT / "data/qa/osm_road_frame_correction_impact.contract.json"
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
    builder = load(BUILDER, "coverage_builder_for_source_binding_test")
    validator = load(VALIDATOR, "coverage_source_binding_validator")
    frontier = builder.build_frontier(SOURCE, FRAME, CELLS)
    validator.validate_source_binding(frontier, SOURCE, FRAME, CELLS)

    malformed = json.loads(json.dumps(frontier))
    malformed["source_intersection_evidence_sha256"] = "not-a-sha"
    malformed["frontier_sha256"] = builder.sha256_json({k: v for k, v in malformed.items() if k != "frontier_sha256"})
    expect_fail(
        lambda: validator.validate_source_binding(malformed, SOURCE, FRAME, CELLS),
        "source evidence sha format drift",
    )

    rebound = json.loads(json.dumps(frontier))
    rebound["source_intersection_evidence_sha256"] = "0" * 64
    rebound["frontier_sha256"] = builder.sha256_json({k: v for k, v in rebound.items() if k != "frontier_sha256"})
    expect_fail(
        lambda: validator.validate_source_binding(rebound, SOURCE, FRAME, CELLS),
        "source evidence binding drift",
    )

    injected = json.loads(json.dumps(frontier))
    injected["noncanonical_extension"] = {"source_registration_ready": True}
    injected["frontier_sha256"] = builder.sha256_json({k: v for k, v in injected.items() if k != "frontier_sha256"})
    expect_fail(
        lambda: validator.validate_source_binding(injected, SOURCE, FRAME, CELLS),
        "frontier source binding drift",
    )

    print("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
