from __future__ import annotations

import importlib.util
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
TOOL = PROJECT / "tools/city_machine/acquire_municipality_road_source.py"
MANIFEST = PROJECT / "data/source_plans/auderghem_road_source_acquisition.json"


def load_tool():
    spec = importlib.util.spec_from_file_location("municipality_road_acquisition_wgs84", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def raw_with_point(lat, lon):
    return {
        "osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"},
        "elements": [{
            "type": "way",
            "id": 123,
            "tags": {"highway": "residential", "name": "Teststraat"},
            "geometry": [{"lat": lat, "lon": lon}, {"lat": 50.8421, "lon": 4.3482}],
        }],
    }


def test_intake_rejects_non_finite_and_out_of_domain_wgs84_coordinates() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    invalid_points = [
        (float("nan"), 4.3480),
        (float("inf"), 4.3480),
        (91.0, 4.3480),
        (-91.0, 4.3480),
        (50.8420, 181.0),
        (50.8420, -181.0),
        (True, 4.3480),
        ("50.8420", 4.3480),
    ]
    for lat, lon in invalid_points:
        try:
            module.build_outputs(manifest, raw_with_point(lat, lon))
        except SystemExit as exc:
            assert "invalid WGS84 coordinate" in str(exc)
        else:
            raise AssertionError(f"invalid WGS84 coordinate escaped intake: lat={lat!r} lon={lon!r}")
