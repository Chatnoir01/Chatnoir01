from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_tree_lod_boundary_margin_short_circuits_exact_scan_safely() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    assert "var _tree_lod_boundary_margin_m := 0.0" in source
    assert "var _tree_lod_boundary_margin_radius_m := INF" in source
    assert "func _update_tree_lod_boundary_margin(" not in source, (
        "boundary margin must stay single-pass; do not restore the second full rendered-tree scan"
    )

    start = source.index("func _tree_lod_boundary_crossed(anchor: Vector3) -> bool:")
    end = source.index("\nfunc _clear_tree_foliage_batches", start)
    boundary = source[start:end]
    assert "_tree_lod_boundary_margin_radius_m != tree_full_detail_radius_m" in boundary
    assert "return true" in boundary
    assert "var anchor_dx := anchor.x - _last_tree_lod_anchor.x" in boundary
    assert "var anchor_dz := anchor.z - _last_tree_lod_anchor.z" in boundary
    assert "var anchor_distance_sq := anchor_dx * anchor_dx + anchor_dz * anchor_dz" in boundary
    assert "if anchor_distance_sq < _tree_lod_boundary_margin_m * _tree_lod_boundary_margin_m:" in boundary
    assert "return false" in boundary
    assert "var detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m" in boundary
    assert "var was_near := old_dx * old_dx + old_dz * old_dz <= detail_radius_sq" in boundary
    assert "var is_near := new_dx * new_dx + new_dz * new_dz <= detail_radius_sq" in boundary

    foliage_start = source.index("func _build_tree_foliage_batches(")
    foliage_end = source.index("\nfunc _build_tree_batches", foliage_start)
    foliage = source[foliage_start:foliage_end]
    assert "var minimum_boundary_margin := INF" in foliage
    assert "var radial_distance := sqrt(distance_sq)" in foliage
    assert "minimum_boundary_margin = min(minimum_boundary_margin, abs(radial_distance - tree_full_detail_radius_m))" in foliage
    assert "_tree_lod_boundary_margin_radius_m = tree_full_detail_radius_m" in foliage
    assert "max(0.0, minimum_boundary_margin - BOUNDS_NUMERIC_EPSILON_M)" in foliage

    refresh_start = source.index("func _refresh_tree_lod(anchor: Vector3) -> void:")
    refresh_end = source.index("\nfunc _refresh(force: bool) -> void:", refresh_start)
    refresh = source[refresh_start:refresh_end]
    assert "_build_tree_foliage_batches(_rendered_trees, anchor, true)" in refresh
    assert "_last_tree_lod_anchor = anchor" in refresh
    assert "_update_tree_lod_boundary_margin()" not in refresh

    rebuild_start = source.index("func _rebuild(anchor: Vector3) -> void:")
    rebuild_end = source.index("\nfunc _batch", rebuild_start)
    rebuild = source[rebuild_start:rebuild_end]
    assert "_last_tree_lod_anchor = anchor" in rebuild
    assert "_build_tree_batches(trees, true)" in rebuild
    assert "_update_tree_lod_boundary_margin()" not in rebuild

    reset_start = source.index("func _reset_loaded_source_state() -> void:")
    reset_end = source.index("\nfunc _load_points", reset_start)
    reset = source[reset_start:reset_end]
    assert "_tree_lod_boundary_margin_m = 0.0" in reset
    assert "_tree_lod_boundary_margin_radius_m = INF" in reset


if __name__ == "__main__":
    verify_tree_lod_boundary_margin_short_circuits_exact_scan_safely()
    print("OSM_TREE_LOD_BOUNDARY_MARGIN_OK")
