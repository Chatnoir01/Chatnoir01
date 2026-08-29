#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tools" / "validate_road_destination_grid_identity.py"
READINESS = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"

spec = importlib.util.spec_from_file_location("road_grid_identity", VALIDATOR)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_real_readiness_grid_identity_is_exact() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    result = module.validate_readiness(readiness)
    assert result["destination_count"] == 96
    assert result["mapped_cell_count"] == 4


def test_forged_grid_cell_id_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    original = destination["grid_cell_id"]
    destination["grid_cell_id"] = "E999999_N999999"
    assert destination["cell_id"] != "bxl-e999999-n999999-s500"
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "grid cell identity drift" in str(exc)
    else:
        raise AssertionError(f"forged grid_cell_id {original} -> {destination['grid_cell_id']} did not fail closed")


def test_cell_id_bbox_disagreement_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    destination["cell_bbox"] = [147000.0, 169500.0, 147500.0, 170000.0]
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "cell bbox identity drift" in str(exc)
    else:
        raise AssertionError("cell_id/bbox disagreement did not fail closed")


if __name__ == "__main__":
    test_real_readiness_grid_identity_is_exact()
    test_forged_grid_cell_id_fails_closed()
    test_cell_id_bbox_disagreement_fails_closed()
    print("ROAD_CELL_GRID_IDENTITY_TEST_OK")
