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


def raw_with_geometry(geometry):
    return {
        "osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"},
        "elements": [{
            "type": "way",
            "id": 123,
            "tags": {"highway": "residential", "name": "Teststraat"},
            "geometry": geometry,
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
            assert "invalid WGS84 road geometry" in str(exc)
        else:
            raise AssertionError(f"invalid WGS84 coordinate escaped intake: lat={lat!r} lon={lon!r}")


def test_intake_rejects_degenerate_wgs84_road_geometry_before_projection() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)

    def forbidden_convert(*_args, **_kwargs):
        raise AssertionError("projection must not run for degenerate WGS84 geometry")

    module.convert = forbidden_convert
    degenerate_geometries = [
        [{"lat": 50.8420, "lon": 4.3480}],
        [
            {"lat": 50.8420, "lon": 4.3480},
            {"lat": 50.8420, "lon": 4.3480},
            {"lat": 50.8420, "lon": 4.3480},
        ],
    ]
    for geometry in degenerate_geometries:
        try:
            module.build_outputs(manifest, raw_with_geometry(geometry))
        except SystemExit as exc:
            assert "invalid WGS84 road geometry" in str(exc)
        else:
            raise AssertionError("degenerate WGS84 road geometry escaped intake")


def test_repeated_vertices_are_allowed_when_two_distinct_positions_exist() -> None:
    module = load_tool()
    raw = raw_with_geometry([
        {"lat": 50.8420, "lon": 4.3480},
        {"lat": 50.8420, "lon": 4.3480},
        {"lat": 50.8421, "lon": 4.3482},
    ])
    module.validate_wgs84_geometry(raw)


def test_intake_rejects_invalid_projected_geometry_before_hashing() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    raw = raw_with_geometry([
        {"lat": 50.8420, "lon": 4.3480},
        {"lat": 50.8421, "lon": 4.3482},
    ])

    invalid_converted = [
        {"roads": [{"osm_id": 123, "class": "residential", "drivable": True, "points": [[float("nan"), 0.0], [1.0, 1.0]]}], "stats": {"drivable_roads": 1}},
        {"roads": [{"osm_id": 123, "class": "residential", "drivable": True, "points": [[0.0, 0.0], [0.0, 0.0]]}], "stats": {"drivable_roads": 1}},
    ]
    for converted in invalid_converted:
        module.convert = lambda *_args, _converted=converted, **_kwargs: _converted
        try:
            module.build_outputs(manifest, raw)
        except SystemExit as exc:
            assert "invalid projected road geometry" in str(exc)
        else:
            raise AssertionError("invalid projected road geometry escaped hashing/receipt")
