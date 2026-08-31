import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game/scripts/brussels_corridor_tree_runtime.gd"
ZONE = ROOT / "data/osm/zones/anneessens/environment.game.json"
LEGACY = ROOT / "data/osm/anneessens_environment_points.game.json"
SLICE = ROOT / "data/osm/vertical_slice_01.game.json"

EXPECTED_SOURCE = "OpenStreetMap contributors via Overpass API"
EXPECTED_LICENSE = "ODbL-1.0"
EXPECTED_ZONE = "anneessens"
EXPECTED_SLICE_TREE_COUNT = 273


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def normalized_points(payload):
    points = payload.get("environment_points", payload.get("points", []))
    return [
        (int(p["osm_id"]), str(p["kind"]), tuple(float(v) for v in p["position"]))
        for p in points
        if isinstance(p, dict)
    ]


def main():
    runtime = RUNTIME.read_text(encoding="utf-8")
    zone = load_json(ZONE)
    legacy = load_json(LEGACY)
    corridor = load_json(SLICE)

    assert 'const ANNEESSENS_DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"' in runtime, (
        "corridor-tree duplicate suppression path changed without updating this cross-source ownership contract"
    )
    assert runtime.count("ANNEESSENS_DATA_PATH") == 2, (
        "Anneessens preowner source must remain a single explicit runtime input plus one loader use"
    )
    assert 'const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"' in runtime, (
        "corridor tree rendered source changed without updating the preowner source lock"
    )

    assert zone["format"] == "grand-bruxelles-osm-zone-environment-v1"
    assert zone["source"] == EXPECTED_SOURCE
    assert zone["license"] == EXPECTED_LICENSE
    assert zone["zone"] == EXPECTED_ZONE
    assert zone["coordinate_space"] == "game_xz_m"

    assert legacy["format"] == "grand-bruxelles-osm-environment-points-v1"
    assert legacy["source"] == EXPECTED_SOURCE
    assert legacy["license"] == EXPECTED_LICENSE
    assert legacy["zone"] == EXPECTED_ZONE

    assert corridor["format"] == "grand-bruxelles-osm-v1"
    assert corridor["source"] == EXPECTED_SOURCE
    assert corridor["license"] == EXPECTED_LICENSE

    zone_points = normalized_points(zone)
    legacy_points = normalized_points(legacy)
    corridor_points = normalized_points(corridor)
    corridor_trees = [point for point in corridor_points if point[1] == "tree"]

    assert len(zone_points) == 7
    assert all(kind == "tree" for _, kind, _ in zone_points)
    assert len({osm_id for osm_id, _, _ in zone_points}) == len(zone_points)
    assert len({osm_id for osm_id, _, _ in legacy_points}) == len(legacy_points)
    assert len(corridor_trees) == EXPECTED_SLICE_TREE_COUNT
    assert len({osm_id for osm_id, _, _ in corridor_trees}) == len(corridor_trees)

    # The corridor runtime currently consumes the compact legacy seven-tree preowner list,
    # while AnneessensOsmFurnitureRuntime consumes the normalized zone artifact. Lock them
    # as one semantic ownership set so future normalization cannot create duplicates/holes.
    assert zone_points == legacy_points, (
        "Anneessens normalized owner source and corridor preowner exclusion source diverged"
    )

    # Equality between the two Anneessens copies is not sufficient: both copies could drift
    # together and still suppress seven unrelated corridor trees. Anchor every preowned id and
    # position to the exact source tuples rendered by BrusselsCorridorTreeRuntime.
    corridor_tree_by_id = {osm_id: (kind, position) for osm_id, kind, position in corridor_trees}
    for osm_id, kind, position in zone_points:
        assert osm_id in corridor_tree_by_id, (
            f"Anneessens preowned tree {osm_id} is absent from vertical_slice_01 rendered tree source"
        )
        assert corridor_tree_by_id[osm_id] == (kind, position), (
            f"Anneessens preowned tree {osm_id} position/kind drifted from vertical_slice_01 rendered source"
        )

    selection_ids = [int(v) for v in zone.get("selection", {}).get("osm_ids", [])]
    assert selection_ids == [osm_id for osm_id, _, _ in zone_points]
    assert int(zone.get("stats", {}).get("tree", -1)) == len(zone_points)
    assert int(zone.get("stats", {}).get("total", -1)) == len(zone_points)

    print(
        "SHARED_ENVIRONMENT_CORRIDOR_TREE_PREOWNER_SOURCE_LOCK_OK: "
        f"trees={len(zone_points)} semantic_sets=identical rendered_source_subset=locked "
        f"corridor_trees={len(corridor_trees)} source=OSM license=ODbL-1.0 geometry_delta=0"
    )


if __name__ == "__main__":
    main()
