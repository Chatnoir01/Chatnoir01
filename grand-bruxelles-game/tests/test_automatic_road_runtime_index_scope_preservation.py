from pathlib import Path

ROOT = Path(__file__).parents[1]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def test_source_auth_fix_preserves_existing_spawn_safety_pipeline() -> None:
    """Prevent a focused runtime-index auth patch from deleting unrelated proven safety logic."""
    text = RESOLVER.read_text(encoding="utf-8")

    required_functions = (
        "func _source_building_polygons(",
        "func _point_inside_any_source_building(",
        "func _segment_clear_of_source_buildings(",
        "func _source_view_corridor_clearance(",
        "func _source_building_clearance(",
        "func _source_endpoint_continuation_count(",
        "func _safe_viewpoint(",
        "func _nearby_corridor_anchor(",
        "func _corridor_oriented_target(",
        "func apply_to_player(",
    )
    for signature in required_functions:
        assert signature in text, f"focused source-auth change removed unrelated resolver contract: {signature}"

    loader_start = text.index("func _load_runtime_index() -> bool:")
    loader_end = text.index("\n\nfunc runtime_index_road_count()", loader_start)
    loader = text[loader_start:loader_end]

    # The auth correction is allowed to mutate the loader, not erase downstream
    # source-building, viewpoint, collision or player-application contracts.
    assert "_road_source_path_by_id.clear()" in loader
    assert "_source_sha_by_path.clear()" in loader
    assert "_runtime_index_valid = false" in loader
