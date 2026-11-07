from __future__ import annotations

import importlib.util
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LOCK = PROJECT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
AUDERGHEM = PROJECT / "data/source_plans/auderghem_road_source_acquisition.json"
TOOL = PROJECT / "tools/city_machine/acquire_municipality_road_source.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("municipality_road_source_acquisition_transport", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_timeouts_are_part_of_every_locked_acquisition_profile() -> None:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    manifest = json.loads(AUDERGHEM.read_text(encoding="utf-8"))
    expected = {"query_timeout_seconds": 120, "transport_timeout_seconds": 150}
    for key, value in expected.items():
        assert lock["source"][key] == value
        assert manifest["source"][key] == value


def test_query_timeout_is_consumed_from_locked_manifest() -> None:
    tool = load_tool()
    manifest = {
        "municipality": {"osm_relation_id": 58263},
        "source": {"highway_classes": ["residential"], "query_timeout_seconds": 37},
    }
    query = tool.build_query(manifest)
    assert "[timeout:37]" in query
    assert "[timeout:120]" not in query


def test_transport_timeout_is_consumed_from_locked_manifest() -> None:
    source = TOOL.read_text(encoding="utf-8")
    assert '"query_timeout_seconds": 120' in source
    assert '"transport_timeout_seconds": 150' in source
    assert "def fetch(endpoint: str, query: str, retries: int, transport_timeout_seconds: int)" in source
    assert "urllib.request.urlopen(request, timeout=transport_timeout_seconds)" in source
    assert "urlopen(request, timeout=150)" not in source
