from __future__ import annotations

import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
TOOL = PROJECT / "tools/city_machine/acquire_municipality_road_source.py"
MANIFEST = PROJECT / "data/source_plans/auderghem_road_source_acquisition.json"


def load_tool():
    spec = importlib.util.spec_from_file_location("municipality_road_acquisition_identity", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def valid_way(way_id=123, highway="residential"):
    return {
        "type": "way",
        "id": way_id,
        "tags": {"highway": highway, "name": "Teststraat"},
        "geometry": [
            {"lat": 50.8420, "lon": 4.3480},
            {"lat": 50.8421, "lon": 4.3482},
        ],
    }


def raw(elements):
    return {
        "osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"},
        "elements": elements,
    }


def assert_rejected(elements, expected):
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    try:
        module.build_outputs(manifest, raw(elements))
    except SystemExit as exc:
        assert expected in str(exc)
    else:
        raise AssertionError(f"malformed Overpass road identity escaped intake: {elements!r}")


def test_non_way_element_fails_closed() -> None:
    element = valid_way()
    element["type"] = "node"
    assert_rejected([element], "invalid Overpass road element")


def test_non_integer_and_boolean_way_ids_fail_closed() -> None:
    assert_rejected([valid_way("123")], "invalid OSM way id")
    assert_rejected([valid_way(True)], "invalid OSM way id")
    assert_rejected([valid_way(0)], "invalid OSM way id")


def test_duplicate_way_id_fails_closed() -> None:
    assert_rejected([valid_way(123), valid_way(123)], "duplicate OSM way id")


def test_missing_or_disallowed_highway_tag_fails_closed() -> None:
    element = valid_way()
    element["tags"] = {"name": "Teststraat"}
    assert_rejected([element], "invalid highway class")
    assert_rejected([valid_way(123, "footway")], "invalid highway class")
