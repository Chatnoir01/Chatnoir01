#!/usr/bin/env python3
"""Regressions for corrected Grand-Place canonical-registration review."""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/qa/review_grand_place_correct_canonical_registration.py"
CONTRACT = Path("data/qa/grand_place_correct_canonical_registration_review.contract.json")
LOCK = Path("data/provenance/grand_place_correct_canonical_registration.review.json")
BASE = "3e49d0b5933b5c6588d164a8bfec997860c9c117"
TARGET = "bxl-e148500-n170500-s500"

spec = importlib.util.spec_from_file_location("gp_review", TOOL)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def expect_failure(root: Path, needle: str) -> None:
    try:
        module.review(root, CONTRACT, BASE)
    except (AssertionError, FileNotFoundError, KeyError, json.JSONDecodeError) as exc:
        assert needle in str(exc), (needle, str(exc))
    else:
        raise AssertionError(f"expected fail-closed error containing {needle!r}")


def clone_minimal() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="gp-canonical-review-"))
    for relative in [
        CONTRACT,
        Path("data/provenance/grand_place_correct_urbis_source_cell.measurement.json"),
        Path("data/provenance/grand_place_correct_source_cell_municipality.measurement.json"),
        Path("data/provenance/brussels_registered_cell_manifest_index.json"),
    ]:
        dst = tmp / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, dst)
    src_cell = ROOT / "data/urbis/remaining_brussels/cells" / TARGET
    dst_cell = tmp / "data/urbis/remaining_brussels/cells" / TARGET
    shutil.copytree(src_cell, dst_cell)
    return tmp


def main() -> None:
    result = module.review(ROOT, CONTRACT, BASE)
    assert result["status"] == "READY_FOR_CANONICAL_MANIFEST_REVIEW"
    assert result["municipality_evidence"]["niscode"] == "21004"
    assert result["municipality_evidence"]["coverage_ratio"] == 1.0
    assert result["registered_cell_index"]["target_present"] is False
    assert result["registration_authorized"] is False
    assert result["runtime_mount_authorized"] is False
    assert result["jouable_promotion_authorized"] is False

    # Once the review is accepted, its semantic result must be persisted exactly.
    # This deliberately fails while the lock is absent, giving us a RED before persistence.
    locked = json.loads((ROOT / LOCK).read_text())
    assert locked["semantic_sha256"] == result["semantic_sha256"]
    assert locked == result
    assert locked["registration_authorized"] is False
    assert locked["road_cell_mapping_authorized"] is False
    assert locked["runtime_mount_authorized"] is False
    assert locked["rendered_geometry_authorized"] is False
    assert locked["collision_authorized"] is False
    assert locked["safe_spawn_authorized"] is False
    assert locked["jouable_promotion_authorized"] is False

    root = clone_minimal()
    try:
        raw = root / "data/urbis/remaining_brussels/cells" / TARGET / "raw/buildings.geojson"
        raw.write_bytes(raw.read_bytes() + b"\n")
        expect_failure(root, "raw bytes drifted: buildings")
    finally:
        shutil.rmtree(root)

    root = clone_minimal()
    try:
        municipality = root / "data/provenance/grand_place_correct_source_cell_municipality.measurement.json"
        data = json.loads(municipality.read_text())
        data["municipality_coverage"]["municipality_niscode"] = "21001"
        municipality.write_text(json.dumps(data))
        expect_failure(root, "")
    finally:
        shutil.rmtree(root)

    root = clone_minimal()
    try:
        maturity = root / "data/urbis/remaining_brussels/cells" / TARGET / "maturity.json"
        data = json.loads(maturity.read_text())
        data["maturity"]["gates"]["runtime_geometry"] = True
        maturity.write_text(json.dumps(data))
        expect_failure(root, "source maturity bytes drifted")
    finally:
        shutil.rmtree(root)

    root = clone_minimal()
    try:
        index_path = root / "data/provenance/brussels_registered_cell_manifest_index.json"
        index = json.loads(index_path.read_text())
        index["entries"].append({"cell_id": TARGET})
        index["registered_cell_count"] += 1
        index_path.write_text(json.dumps(index))
        expect_failure(root, "target is already registered")
    finally:
        shutil.rmtree(root)

    print("GRAND_PLACE_CORRECT_CANONICAL_REVIEW_REGRESSIONS_OK cases=6 lock_exact=true fail_closed=true")


if __name__ == "__main__":
    main()
