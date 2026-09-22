from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def test_generated_roads_are_watched_before_anneessens_eligibility_filters():
    """An initially ineligible road can later mutate into the proxy build set."""
    source = RUNTIME.read_text(encoding="utf-8")
    build = source.split("func _build_from_existing_osm_roads() -> bool:", 1)[1]
    build = build.split("func _add_sidewalk_pair", 1)[0]

    watch = build.index("_watch_alignment_road_mutations(road)")
    radius = build.index("center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M")
    size = build.index("road.size.z < 1.0 or road.size.x < 2.0")

    assert watch < radius
    assert watch < size
