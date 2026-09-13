#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = Path(__file__).with_name("validate_road_destination_readiness_unique_identity.py")
CATALOG = ROOT / "data/qa/road_destination_readiness_catalog.json"


def _load_validator():
    spec = importlib.util.spec_from_file_location("readiness_unique_identity", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load readiness unique identity validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_boolean_destination_count_is_rejected_even_for_single_row() -> None:
    validator = _load_validator()
    catalog = validator._load_strict(CATALOG)
    candidate = copy.deepcopy(catalog)
    candidate["destinations"] = [copy.deepcopy(catalog["destinations"][0])]
    candidate["destination_count"] = True

    try:
        validator.validate_catalog(candidate)
    except ValueError as exc:
        assert "destination_count" in str(exc)
    else:
        raise AssertionError("boolean destination_count=True was accepted as integer count 1")
