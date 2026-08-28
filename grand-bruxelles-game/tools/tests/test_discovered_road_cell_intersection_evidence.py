#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "build_discovered_road_cell_intersection_evidence.py"
SOURCE = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
FRAME = ROOT / "data" / "qa" / "osm_road_frame_correction_impact.contract.json"
CELLS = ROOT / "data" / "provenance" / "brussels_registered_cell_manifest_index.json"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_fail(fn, needle: str) -> None:
    try:
        fn()
    except (SystemExit, RuntimeError) as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected failure containing {needle!r}")


def main() -> int:
    tool = load(TOOL, "discovered_road_cell_intersection_evidence")
    evidence = tool.build_evidence(SOURCE, FRAME, CELLS)
    tool.validate_evidence(evidence, SOURCE, FRAME, CELLS)

    assert evidence["format"] == "grand-bruxelles-discovered-road-cell-intersection-evidence-v1"
    assert evidence["source_crs"] == "EPSG:31370"
    assert evidence["assignment_authorized"] is False
    assert evidence["municipality_inference_authorized"] is False
    assert evidence["runtime_mount_authorized"] is False
    assert evidence["jouable_authorized"] is False
    assert evidence["candidate_count"] > 0
    assert evidence["candidate_count"] == len(evidence["candidates"])

    for row in evidence["candidates"]:
        assert row["state"] == "DISCOVERED"
        assert row["registration_ready"] is False
        assert row["municipalities"] is None
        assert row["proposed_municipality_niscodes"] is None
        assert row["intersection_count"] == len(row["intersections"])
        for hit in row["intersections"]:
            assert hit["crs"] == "EPSG:31370"
            assert hit["manifest_path"].startswith("data/cell_manifests/")
            assert len(hit["manifest_sha256"]) == 64

    tampered = json.loads(json.dumps(evidence))
    tampered["assignment_authorized"] = True
    tampered["evidence_sha256"] = tool.sha256_json({k: v for k, v in tampered.items() if k != "evidence_sha256"})
    expect_fail(lambda: tool.validate_evidence(tampered, SOURCE, FRAME, CELLS), "assignment authorization opened")

    tampered = json.loads(json.dumps(evidence))
    tampered["candidates"][0]["municipalities"] = ["21001"]
    tampered["evidence_sha256"] = tool.sha256_json({k: v for k, v in tampered.items() if k != "evidence_sha256"})
    expect_fail(lambda: tool.validate_evidence(tampered, SOURCE, FRAME, CELLS), "municipality inference leaked")

    tampered = json.loads(json.dumps(evidence))
    if tampered["candidates"][0]["intersections"]:
        tampered["candidates"][0]["intersections"][0]["manifest_sha256"] = "0" * 64
        tampered["evidence_sha256"] = tool.sha256_json({k: v for k, v in tampered.items() if k != "evidence_sha256"})
        expect_fail(lambda: tool.validate_evidence(tampered, SOURCE, FRAME, CELLS), "source binding drift")

    # The registered-cell index must not be able to redefine the spatial identity
    # of immutable manifest bytes. The builder uses index bboxes for intersection
    # math, so both cell_id and bbox must agree with the referenced manifest.
    cell_index = json.loads(CELLS.read_text(encoding="utf-8"))
    tampered_cells = json.loads(json.dumps(cell_index))
    tampered_cells["entries"][0]["bbox"][0] += 1.0
    expect_fail(lambda: tool._cell_rows(ROOT, tampered_cells), "cell manifest content drift")

    tampered_cells = json.loads(json.dumps(cell_index))
    tampered_cells["entries"][0]["cell_id"] = "bxl-e000000-n000000-s500"
    expect_fail(lambda: tool._cell_rows(ROOT, tampered_cells), "cell manifest content drift")

    print("DISCOVERED_ROAD_CELL_INTERSECTION_EVIDENCE_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
