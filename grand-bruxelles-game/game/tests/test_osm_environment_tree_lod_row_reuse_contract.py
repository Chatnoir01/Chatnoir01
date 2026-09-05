from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def section(source: str, start_marker: str, end_marker: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


def verify_tree_lod_refresh_reuses_selected_rows_without_dictionary_churn() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    refresh_lod = section(source, "func _refresh_tree_lod(anchor: Vector3) -> void:", "\nfunc _refresh(force: bool)")
    rebuild = section(source, "func _rebuild(anchor: Vector3) -> void:", "\nfunc _batch(")

    assert "_build_tree_foliage_batches_for_anchor(_rendered_trees, anchor)" in refresh_lod, (
        "tree-only LOD refresh must consume the already selected tree rows directly"
    )
    assert "rows.append(" not in refresh_lod, (
        "tree-only LOD refresh must not allocate one transient Dictionary per rendered tree"
    )
    assert '"distance_sq"' not in refresh_lod, (
        "tree-only LOD refresh must recompute distance at foliage emission without materializing transient rows"
    )

    assert "_rendered_trees = trees" in rebuild
    assert "_rendered_trees = trees.duplicate(true)" not in rebuild, (
        "full rebuild owns the selected tree row Array already; deep-copying it duplicates up to max_trees rows"
    )

    anchor_builder = section(
        source,
        "func _build_tree_foliage_batches_for_anchor(rows: Array, anchor: Vector3) -> void:",
        "\nfunc _build_tree_batches(",
    )
    assert "var dx := base.x - anchor.x" in anchor_builder
    assert "var dz := base.z - anchor.z" in anchor_builder
    assert "dx * dx + dz * dz" in anchor_builder
    assert "_build_tree_foliage_batches_from_distances" in anchor_builder, (
        "anchor refresh path must retain the canonical foliage batching implementation"
    )


if __name__ == "__main__":
    verify_tree_lod_refresh_reuses_selected_rows_without_dictionary_churn()
    print("OSM_TREE_LOD_ROW_REUSE_OK")
