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


def mutate_identity(registry, evidence, field, value):
    registry = copy.deepcopy(registry)
    evidence = copy.deepcopy(evidence)
    registry_row = registry["municipalities"][0]
    nis = registry_row["niscode"]
    evidence_row = evidence_row_for_nis(evidence, nis)
    registry_row[field] = value
    evidence_row[field] = value
    if field == "niscode" and "artifact" in evidence_row:
        evidence_row["artifact"]["name"] = f"road-source-{value}-{evidence_row['id']}"
    elif field == "id" and "artifact" in evidence_row:
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


@pytest.mark.parametrize("name", [" Auderghem", "Auderghem ", "\tAuderghem"])
def test_catalog_rejects_coordinated_noncanonical_municipality_name_whitespace(name):
    registry, evidence = mutate_identity(load(REGISTRY), load(EVIDENCE), "name", name)
    with pytest.raises(SystemExit, match="municipality identity domain"):
        build_catalog(registry, evidence)


def test_catalog_rejects_coordinated_duplicate_municipality_id():
    registry = copy.deepcopy(load(REGISTRY))
    evidence = copy.deepcopy(load(EVIDENCE))
    first = registry["municipalities"][0]
    second = registry["municipalities"][1]
    duplicate_id = first["id"]
    second["id"] = duplicate_id
    evidence_row = evidence_row_for_nis(evidence, second["niscode"])
    evidence_row["id"] = duplicate_id
    if "artifact" in evidence_row:
        evidence_row["artifact"]["name"] = f"road-source-{evidence_row['niscode']}-{duplicate_id}"

    with pytest.raises(SystemExit, match="duplicate municipality id"):
        build_catalog(registry, evidence)


def test_catalog_rejects_coordinated_duplicate_municipality_name():
    registry = copy.deepcopy(load(REGISTRY))
    evidence = copy.deepcopy(load(EVIDENCE))
    first = registry["municipalities"][0]
    second = registry["municipalities"][1]
    duplicate_name = first["name"]
    second["name"] = duplicate_name
    evidence_row = evidence_row_for_nis(evidence, second["niscode"])
    evidence_row["name"] = duplicate_name

    with pytest.raises(SystemExit, match="duplicate municipality name"):
        build_catalog(registry, evidence)


def test_catalog_rejects_noncanonical_registry_municipality_order():
    registry = copy.deepcopy(load(REGISTRY))
    evidence = copy.deepcopy(load(EVIDENCE))
    registry["municipalities"][0], registry["municipalities"][1] = (
        registry["municipalities"][1],
        registry["municipalities"][0],
    )

    with pytest.raises(SystemExit, match="registry municipality order drift"):
        build_catalog(registry, evidence)
