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


def test_catalog_rejects_partition_nis_drift_from_pinned_evidence_baseline():
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated_registry = copy.deepcopy(registry)
    mutated_evidence = copy.deepcopy(evidence)

    source_row = mutated_evidence["unresolved_acquisitions"][0]
    old_nis = source_row["niscode"]
    replacement_nis = "21999"
    assert replacement_nis not in {
        row["niscode"] for row in mutated_registry["municipalities"]
    }

    source_row["niscode"] = replacement_nis
    registry_row = next(
        row for row in mutated_registry["municipalities"] if row["niscode"] == old_nis
    )
    registry_row["niscode"] = replacement_nis

    with pytest.raises(SystemExit, match="evidence partition baseline drift"):
        build_catalog(mutated_registry, mutated_evidence)
