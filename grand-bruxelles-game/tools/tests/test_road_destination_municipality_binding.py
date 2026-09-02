#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tools/validate_road_destination_municipality_binding.py"
READINESS = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"

spec = importlib.util.spec_from_file_location("municipality_binding", VALIDATOR)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def _readiness() -> dict:
    return json.loads(READINESS.read_text(encoding="utf-8"))


def _must_fail(mutator, needle: str) -> None:
    data = _readiness()
    mutator(data["destinations"][0])
    try:
        module.validate(data)
    except SystemExit as exc:
        assert needle in str(exc)
    else:
        raise AssertionError(f"expected fail-closed municipality binding error containing {needle!r}")


def test_live_catalog_matches_cell_manifest_municipalities() -> None:
    result = module.validate(_readiness())
    assert result["destinations"] == 96
    assert result["cells"] == 4


def test_rejects_niscode_alias_drift() -> None:
    _must_fail(lambda d: d["municipality_niscodes"].__setitem__(0, "99999"), "municipality_niscodes drift")


def test_rejects_coverage_ratio_drift() -> None:
    _must_fail(lambda d: d["municipalities"][0].__setitem__("coverage_ratio", 0.5), "municipality evidence drift")


def test_rejects_inspire_identity_drift() -> None:
    _must_fail(lambda d: d["municipalities"][0].__setitem__("inspire_id", "https://example.invalid/municipality"), "municipality evidence drift")


def main() -> None:
    test_live_catalog_matches_cell_manifest_municipalities()
    test_rejects_niscode_alias_drift()
    test_rejects_coverage_ratio_drift()
    test_rejects_inspire_identity_drift()
    print("ROAD_DESTINATION_MUNICIPALITY_BINDING_REGRESSIONS_OK tests=4")


if __name__ == "__main__":
    main()
