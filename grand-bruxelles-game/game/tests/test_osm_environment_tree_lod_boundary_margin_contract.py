from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_tree_lod_boundary_margin_short_circuits_exact_scan_safely() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    assert "var _tree_lod_boundary_margin_m := 0.0" in source
    assert "var _tree_lod_boundary_margin_radius_m := INF" in source
    assert "func _update_tree_lod_boundary_margin() -> void:" in source
    assert "minimum_margin - BOUNDS_NUMERIC_EPSILON_M" in source

    start = source.index("func _tree_lod_boundary_crossed(anchor: Vector3) -> bool:")
    end = source.index("\nfunc _clear_tree_foliage_batches", start)
    boundary = source[start:end]
    assert "_tree_lod_boundary_margin_radius_m == tree_full_detail_radius_m" in boundary
    assert "var anchor_dx := anchor.x - _last_tree_lod_anchor.x" in boundary
    assert "var anchor_dz := anchor.z - _last_tree_lod_anchor.z" in boundary
    assert "var anchor_distance_sq := anchor_dx * anchor_dx + anchor_dz * anchor_dz" in boundary
    assert "if anchor_distance_sq < _tree_lod_boundary_margin_m * _tree_lod_boundary_margin_m:" in boundary
    assert "return false" in boundary

    refresh_start = source.index("func _refresh_tree_lod(anchor: Vector3) -> void:")
    refresh_end = source.index("\nfunc _refresh(force: bool) -> void:", refresh_start)
    refresh = source[refresh_start:refresh_end]
    assert "_last_tree_lod_anchor = anchor" in refresh
    assert "_update_tree_lod_boundary_margin()" in refresh

    rebuild_start = source.index("func _rebuild(anchor: Vector3) -> void:")
    rebuild_end = source.index("\nfunc _batch", rebuild_start)
    rebuild = source[rebuild_start:rebuild_end]
    assert "_last_tree_lod_anchor = anchor" in rebuild
    assert "_update_tree_lod_boundary_margin()" in rebuild

    reset_start = source.index("func _reset_loaded_source_state() -> void:")
    reset_end = source.index("\nfunc _load_points", reset_start)
    reset = source[reset_start:reset_end]
    assert "_tree_lod_boundary_margin_m = 0.0" in reset
    assert "_tree_lod_boundary_margin_radius_m = INF" in reset


if __name__ == "__main__":
    verify_tree_lod_boundary_margin_short_circuits_exact_scan_safely()
    print("OSM_TREE_LOD_BOUNDARY_MARGIN_OK")
