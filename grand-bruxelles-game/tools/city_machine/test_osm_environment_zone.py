#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("zone_env", HERE / "build_osm_environment_zone.py")
assert SPEC and SPEC.loader
zone_env = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(zone_env)


def manifest() -> dict:
    return {
        "source_crs": "EPSG:31370",
        "bbox": [144900.0, 173000.0, 147700.0, 175300.0],
        "game_origin": {
            "e": 147868.29422791934,
            "n": 169538.62414926197,
            "altitude": 0.0,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
    }


def test_bbox_and_projection() -> None:
    m = manifest()
    bbox = zone_env.bbox_wgs84(m)
    assert 50.86 < bbox[0] < 50.87
    assert 4.29 < bbox[1] < 4.30
    assert 50.88 < bbox[2] < 50.89
    assert 4.33 < bbox[3] < 4.34

    to_wgs84 = zone_env.Transformer.from_crs("EPSG:31370", "EPSG:4326", always_xy=True)
    e, n = float(m["game_origin"]["e"]) + 100.0, float(m["game_origin"]["n"]) + 200.0
    lon, lat = to_wgs84.transform(e, n)
    raw = {
        "osm3s": {"timestamp_osm_base": "2026-08-17T00:00:00Z"},
        "elements": [
            {"type": "node", "id": 3, "lat": lat, "lon": lon, "tags": {"natural": "tree"}},
            {"type": "node", "id": 2, "lat": lat, "lon": lon, "tags": {"highway": "street_lamp"}},
            {"type": "node", "id": 1, "lat": lat, "lon": lon, "tags": {"barrier": "bollard"}},
            {"type": "node", "id": 9, "lat": lat, "lon": lon, "tags": {"amenity": "bench"}},
        ],
    }
    cache = zone_env.normalize_overpass(raw, bbox)
    assert cache["counts"] == {"tree": 1, "street_lamp": 1, "bollard": 1}
    assert len(cache["elements"]) == 3
    result = zone_env.project_cache(cache, m, "jette")
    assert result["stats"] == {"tree": 1, "street_lamp": 1, "bollard": 1, "total": 3}
    assert [point["kind"] for point in result["environment_points"]] == ["bollard", "street_lamp", "tree"]
    for point in result["environment_points"]:
        assert math.isclose(point["position"][0], 100.0, abs_tol=0.01)
        assert math.isclose(point["position"][1], -200.0, abs_tol=0.01)
    assert result["source"] == zone_env.SOURCE
    assert result["license"] == zone_env.LICENSE
    assert len(result["source_digest"]) == 64


def test_bad_crs_fails_closed() -> None:
    m = manifest()
    m["source_crs"] = "EPSG:4326"
    try:
        zone_env.bbox_wgs84(m)
    except ValueError as exc:
        assert "EPSG:31370" in str(exc)
    else:
        raise AssertionError("bad CRS must fail closed")


if __name__ == "__main__":
    test_bbox_and_projection()
    test_bad_crs_fails_closed()
    print("CITY_MACHINE_OSM_ZONE_TESTS_OK projection=EPSG31370 environment=tree,street_lamp,bollard bad_crs=blocked")
