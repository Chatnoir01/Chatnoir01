import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game/scripts/brussels_corridor_tree_runtime.gd"
ZONE = ROOT / "data/osm/zones/anneessens/environment.game.json"
LEGACY = ROOT / "data/osm/anneessens_environment_points.game.json"

EXPECTED_SOURCE = "OpenStreetMap contributors via Overpass API"
EXPECTED_LICENSE = "ODbL-1.0"
EXPECTED_ZONE = "anneessens"


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

    assert 'const ANNEESSENS_DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"' in runtime, (
        "corridor-tree duplicate suppression must consume the exact normalized Anneessens source owned by AnneessensOsmFurnitureRuntime"
    )
    assert "anneessens_environment_points.game.json" not in runtime, (
        "legacy duplicate preowner source must not remain a second runtime truth"
    )

    assert zone["format"] == "grand-bruxelles-osm-zone-environment-v1"
    assert zone["source"] == EXPECTED_SOURCE
    assert zone["license"] == EXPECTED_LICENSE
    assert zone["zone"] == EXPECTED_ZONE
    assert zone["coordinate_space"] == "game_xz_m"

    zone_points = normalized_points(zone)
    legacy_points = normalized_points(legacy)
    assert len(zone_points) == 7
    assert all(kind == "tree" for _, kind, _ in zone_points)
    assert len({osm_id for osm_id, _, _ in zone_points}) == len(zone_points)

    # Migration safety: current normalized owner source is byte-semantic equivalent
    # to the legacy preowner list, so switching the runtime truth cannot move or add trees.
    assert zone_points == legacy_points, "normalized Anneessens owner source drifted from the legacy seven-tree set"

    selection_ids = [int(v) for v in zone.get("selection", {}).get("osm_ids", [])]
    assert selection_ids == [osm_id for osm_id, _, _ in zone_points]
    assert int(zone.get("stats", {}).get("tree", -1)) == len(zone_points)

    print(
        "SHARED_ENVIRONMENT_CORRIDOR_TREE_PREOWNER_SOURCE_LOCK_OK: "
        f"trees={len(zone_points)} source=OSM license=ODbL-1.0 geometry_delta=0"
    )


if __name__ == "__main__":
    main()
