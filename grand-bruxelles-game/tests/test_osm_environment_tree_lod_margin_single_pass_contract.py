from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/brussels_osm_environment_runtime.gd")


def _function_body(source: str, name: str) -> str:
    marker = f"func {name}("
    start = source.find(marker)
    assert start >= 0, f"missing {name}"
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_tree_lod_margin_is_maintained_in_foliage_pass() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    foliage = _function_body(source, "_build_tree_foliage_batches")
    refresh = _function_body(source, "_refresh_tree_lod")
    rebuild = _function_body(source, "_rebuild")

    # The margin is maintained in the foliage pass that already evaluates each
    # rendered tree. A second full scan helper must not be restored.
    assert "func _update_tree_lod_boundary_margin(" not in source
    assert "_update_tree_lod_boundary_margin()" not in refresh
    assert "_update_tree_lod_boundary_margin()" not in rebuild

    # Preserve the exact near/far semantic while deriving the conservative
    # movement margin from the already-computed distance_sq in that same pass.
    assert "var minimum_boundary_margin := INF" in foliage
    assert "sqrt(distance_sq)" in foliage
    assert "abs(radial_distance - tree_full_detail_radius_m)" in foliage
    assert "minimum_boundary_margin = min(minimum_boundary_margin" in foliage
    assert "_tree_lod_boundary_margin_radius_m = tree_full_detail_radius_m" in foliage
    assert "_tree_lod_boundary_margin_m = 0.0" in foliage
    assert "max(0.0, minimum_boundary_margin - BOUNDS_NUMERIC_EPSILON_M)" in foliage

    # Frozen visual/LOD contract: classification still uses the squared 140 m
    # radius comparison and no threshold/camera/source rescue is introduced.
    assert "var full_detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m" in foliage
    assert "if distance_sq <= full_detail_radius_sq:" in foliage


if __name__ == "__main__":
    test_tree_lod_margin_is_maintained_in_foliage_pass()
    print("OSM_TREE_LOD_MARGIN_SINGLE_PASS_OK")
