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


def test_zero_padded_cell_id_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    assert destination["cell_id"] == "bxl-e147500-n169500-s500"
    destination["cell_id"] = "bxl-e0147500-n0169500-s0500"
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "non-canonical cell id" in str(exc)
    else:
        raise AssertionError("zero-padded cell_id was normalized into canonical identity")


def test_boolean_road_osm_id_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    destination["road_osm_id"] = True
    destination["destination_id"] = "road-1"
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "invalid road identity" in str(exc)
    else:
        raise AssertionError("boolean road_osm_id was coerced to integer identity")


def test_string_road_osm_id_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    destination["road_osm_id"] = "001"
    destination["destination_id"] = "road-1"
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "invalid road identity" in str(exc)
    else:
        raise AssertionError("string road_osm_id was coerced to integer identity")


def test_string_destination_count_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["destination_count"] = str(readiness["destination_count"])
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "destination accounting drift" in str(exc)
    else:
        raise AssertionError("string destination_count was coerced to integer accounting")


def test_string_bbox_coordinate_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    destination["cell_bbox"][0] = str(destination["cell_bbox"][0])
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "invalid cell bbox" in str(exc)
    else:
        raise AssertionError("string bbox coordinate was coerced to numeric identity")


def test_root_jouable_authorization_true_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["authorization"]["jouable_authorized"] = True
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "authorization rail drift" in str(exc)
    else:
        raise AssertionError("top-level JOUABLE authorization rail could be enabled without failing closed")


def test_root_boolean_control_alias_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["jouable"] = True
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "readiness root unknown boolean control field" in str(exc)
    else:
        raise AssertionError("root-level boolean control alias bypassed canonical authorization object")


def test_nested_boolean_control_alias_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["destinations"][0]["metadata"] = {"promotion": {"jouable": True}}
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "destination unknown boolean control field" in str(exc)
        assert "metadata.promotion.jouable" in str(exc)
    else:
        raise AssertionError("nested boolean control alias bypassed destination authorization rails")


def test_destination_render_authorization_true_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["destinations"][0]["render_authorized"] = True
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "destination authorization rail drift" in str(exc)
    else:
        raise AssertionError("per-destination render authorization rail could be enabled without failing closed")


def test_unknown_destination_authorization_rail_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["destinations"][0]["road_cell_mapping_authorized"] = True
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "destination authorization rail drift" in str(exc)
    else:
        raise AssertionError("unknown per-destination authorization rail could be added and enabled without failing closed")


def test_unknown_boolean_control_alias_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["destinations"][0]["jouable"] = True
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "unknown boolean control field" in str(exc)
    else:
        raise AssertionError("unknown boolean control alias bypassed destination authorization rails")


if __name__ == "__main__":
    test_real_readiness_grid_identity_is_exact()
    test_forged_grid_cell_id_fails_closed()
    test_cell_id_bbox_disagreement_fails_closed()
    test_zero_padded_cell_id_fails_closed()
    test_boolean_road_osm_id_fails_closed()
    test_string_road_osm_id_fails_closed()
    test_string_destination_count_fails_closed()
    test_string_bbox_coordinate_fails_closed()
    test_root_jouable_authorization_true_fails_closed()
    test_root_boolean_control_alias_fails_closed()
    test_nested_boolean_control_alias_fails_closed()
    test_destination_render_authorization_true_fails_closed()
    test_unknown_destination_authorization_rail_fails_closed()
    test_unknown_boolean_control_alias_fails_closed()
    print("ROAD_CELL_GRID_IDENTITY_TEST_OK")
