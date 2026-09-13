#!/usr/bin/env python3
from __future__ import annotations

import copy
from pathlib import Path

import validate_road_destination_readiness_canonical_aggregate_identity as validator

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"

catalog = validator.load_catalog(CATALOG)
validator.validate(catalog)

cases = []

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["cell_id"] = " " + candidate["destinations"][0]["cell_id"]
cases.append(("cell_id leading whitespace", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["cell_id"] += " "
cases.append(("cell_id trailing whitespace", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = " " + candidate["destinations"][0]["source_path"]
cases.append(("source_path leading whitespace", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] += " "
cases.append(("source_path trailing whitespace", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = "data/osm/../osm/vertical_slice_01.game.json"
cases.append(("source_path traversal alias", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = "data\\osm\\vertical_slice_01.game.json"
cases.append(("source_path backslash alias", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = "data//osm/vertical_slice_01.game.json"
cases.append(("source_path repeated-separator alias", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = "/data/osm/vertical_slice_01.game.json"
cases.append(("source_path absolute alias", candidate))

candidate = copy.deepcopy(catalog)
candidate["destinations"][0]["source_path"] = "data/osm/\tvertical_slice_01.game.json"
cases.append(("source_path control character", candidate))

for label, candidate in cases:
    try:
        validator.validate(candidate)
    except ValueError:
        continue
    raise AssertionError(f"{label} mutation was accepted")

print(
    "ROAD_DESTINATION_READINESS_CANONICAL_AGGREGATE_IDENTITY_REGRESSION_OK "
    "whitespace_aliases_rejected=true control_aliases_rejected=true source_path_aliases_rejected=true"
)
