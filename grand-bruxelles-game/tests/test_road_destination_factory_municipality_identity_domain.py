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


def mutate_identity(registry, evidence, field, value):
    registry = copy.deepcopy(registry)
    evidence = copy.deepcopy(evidence)
    registry_row = registry["municipalities"][0]
    nis = registry_row["niscode"]
    evidence_row = next(row for row in evidence["successful_acquisitions"] if row["niscode"] == nis)
    registry_row[field] = value
    evidence_row[field] = value
    if field == "niscode":
        evidence_row["artifact"]["name"] = f"road-source-{value}-{evidence_row['id']}"
    elif field == "id":
        evidence_row["artifact"]["name"] = f"road-source-{evidence_row['niscode']}-{value}"
    return registry, evidence


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("niscode", "not-a-nis"),
        ("id", ""),
        ("name", ""),
        ("osm_relation_id", True),
        ("osm_relation_id", 0),
    ],
)
def test_catalog_rejects_coordinated_invalid_municipality_identity(field, value):
    registry, evidence = mutate_identity(load(REGISTRY), load(EVIDENCE), field, value)
    with pytest.raises(SystemExit, match="municipality identity domain"):
        build_catalog(registry, evidence)
