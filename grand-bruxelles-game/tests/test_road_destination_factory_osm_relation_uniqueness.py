from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/city_machine"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from build_road_destination_factory_catalog import build_catalog

REGISTRY = ROOT / "data/source_plans/brussels_missing_road_source_registry.json"
EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def evidence_row_for_nis(evidence, nis):
    rows = evidence["successful_acquisitions"] + evidence["unresolved_acquisitions"]
    return next(row for row in rows if row["niscode"] == nis)


def test_catalog_rejects_duplicate_osm_relation_across_municipalities():
    registry = copy.deepcopy(load(REGISTRY))
    evidence = copy.deepcopy(load(EVIDENCE))

    first = registry["municipalities"][0]
    second = registry["municipalities"][1]
    second["osm_relation_id"] = first["osm_relation_id"]
    evidence_row_for_nis(evidence, second["niscode"])["osm_relation_id"] = first["osm_relation_id"]

    with pytest.raises(SystemExit, match="duplicate OSM relation"):
        build_catalog(registry, evidence)
