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


@pytest.mark.parametrize("field", ["id", "name", "archive_sha256"])
def test_derivation_rejects_duplicate_locked_artifact_identity(field: str):
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated = copy.deepcopy(evidence)
    first = mutated["successful_acquisitions"][0]["artifact"]
    second = mutated["successful_acquisitions"][1]["artifact"]
    second[field] = first[field]

    with pytest.raises(SystemExit, match="duplicate locked artifact identity"):
        build_catalog(registry, mutated)
