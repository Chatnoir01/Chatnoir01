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
        ("workflow", "Grand Bruxelles Wrong Workflow"),
        ("run_id", 1),
        ("source_pr", 1),
        ("source_head_sha", "0" * 40),
    ],
)
def test_catalog_rejects_acquisition_run_provenance_drift(field, mutated_value):
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["acquisition_run"][field] = mutated_value
    with pytest.raises(SystemExit, match="acquisition run provenance drift"):
        build_catalog(registry, mutated)


def test_catalog_rejects_acquisition_run_schema_drift():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    mutated["acquisition_run"]["runtime_ready"] = True
    with pytest.raises(SystemExit, match="acquisition run schema drift"):
        build_catalog(registry, mutated)
