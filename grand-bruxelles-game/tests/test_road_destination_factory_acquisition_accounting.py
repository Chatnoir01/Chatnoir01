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


@pytest.mark.parametrize(
    ("field", "mutated_value"),
    [
        ("expected_municipalities", 15),
        ("successful_acquisitions", 6),
        ("unresolved_acquisitions", 10),
        ("successful_acquisitions", True),
    ],
)
def test_catalog_rejects_acquisition_accounting_drift(field, mutated_value):
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["accounting"][field] = mutated_value
    with pytest.raises(SystemExit, match="evidence accounting"):
        build_catalog(registry, mutated)


def test_catalog_rejects_acquisition_accounting_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["accounting"]["registered"] = 0
    with pytest.raises(SystemExit, match="evidence accounting"):
        build_catalog(registry, mutated)
