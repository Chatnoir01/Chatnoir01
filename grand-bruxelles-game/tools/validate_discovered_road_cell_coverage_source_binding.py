#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools/build_discovered_road_cell_coverage_frontier.py"
EVIDENCE_BUILDER = ROOT / "tools/build_discovered_road_cell_intersection_evidence.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_sha256(value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: source evidence sha format drift")
    return value


def validate_source_binding(frontier: dict[str, Any], source_path: Path, frame_path: Path, cells_path: Path) -> None:
    if not isinstance(frontier, dict):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: frontier object drift")

    builder = load(BUILDER, "coverage_builder_for_source_binding")
    evidence_builder = load(EVIDENCE_BUILDER, "intersection_evidence_for_source_binding")

    builder.validate_structure(frontier)
    stored_source_sha = validate_sha256(frontier.get("source_intersection_evidence_sha256"))

    canonical_evidence = evidence_builder.build_evidence(Path(source_path), Path(frame_path), Path(cells_path))
    canonical_sha = validate_sha256(canonical_evidence.get("evidence_sha256"))
    if stored_source_sha != canonical_sha:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: source evidence binding drift")

    canonical_frontier = builder.build_frontier(Path(source_path), Path(frame_path), Path(cells_path))
    if frontier.get("source_zero_intersection_road_osm_ids") != canonical_frontier.get("source_zero_intersection_road_osm_ids"):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: zero-intersection identity binding drift")
    if frontier.get("candidate_cells") != canonical_frontier.get("candidate_cells"):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: candidate-cell source binding drift")

    # Fail closed on the complete canonical document, not only selected source-derived
    # fields. validate_structure intentionally validates invariants rather than acting as
    # a closed JSON schema, so an injected extension could otherwise be re-signed and
    # survive the partial comparisons above.
    if builder.canonical_json(frontier) != builder.canonical_json(canonical_frontier):
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: frontier source binding drift")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Validate discovered-road coverage frontier source-evidence binding")
    parser.add_argument("--frontier", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--frame", required=True, type=Path)
    parser.add_argument("--cells", required=True, type=Path)
    args = parser.parse_args()

    try:
        frontier = json.loads(args.frontier.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_FAIL: invalid frontier JSON") from exc
    validate_source_binding(frontier, args.source, args.frame, args.cells)
    print("DISCOVERED_ROAD_CELL_COVERAGE_SOURCE_BINDING_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
