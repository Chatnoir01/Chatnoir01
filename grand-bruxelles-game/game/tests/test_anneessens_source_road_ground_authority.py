from pathlib import Path

GROUND_TEST = Path(__file__).with_name("anneessens_automatic_road_ground_support_test.gd")


def test_automatic_road_ground_requires_source_road_authority() -> None:
    text = GROUND_TEST.read_text(encoding="utf-8")
    assert '"kind": "source_road_support"' in text
    assert 'ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"' in text
    assert 'ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"' in text

    # An automatic road destination must be independently supported by the
    # source-backed road collider carrying the exact OSM identity. A generic
    # canonical Ground hit cannot prove road/source continuity.
    assert '"kind": "canonical_ground"' not in text
    assert 'CANONICAL_GROUND_NAME' not in text
