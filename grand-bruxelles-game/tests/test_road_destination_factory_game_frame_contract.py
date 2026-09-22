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
    ("field", "drifted"),
    [
        ("origin_lat", 50.0),
        ("origin_lon", 5.0),
        ("axes", "X=east, Y=up, Z=north"),
        ("units", "kilometres"),
    ],
)
def test_derivation_rejects_coordinated_game_frame_drift(field, drifted):
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)
    mutated_registry = copy.deepcopy(registry)
    mutated_evidence = copy.deepcopy(evidence)
    mutated_registry["game_frame"][field] = drifted
    mutated_evidence["game_frame"][field] = drifted
    with pytest.raises(SystemExit, match="game frame contract drift"):
        build_catalog(mutated_registry, mutated_evidence)
