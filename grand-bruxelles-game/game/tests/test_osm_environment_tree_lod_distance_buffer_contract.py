from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def section(source: str, start_marker: str, end_marker: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


def verify_tree_lod_refresh_avoids_transient_distance_buffer() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    refresh_lod = section(source, "func _refresh_tree_lod(anchor: Vector3) -> void:", "\nfunc _refresh(force: bool)")
    foliage = section(source, "func _build_tree_foliage_batches(", "\nfunc _build_tree_batches(")

    assert "_build_tree_foliage_batches(_rendered_trees, anchor)" in refresh_lod, (
        "tree-only LOD refresh must classify directly from selected rows and the current anchor"
    )
    assert "var distances" not in foliage
    assert "distances.append" not in foliage
    assert "_build_tree_foliage_batches_from_distances" not in source, (
        "tree LOD must not allocate a transient per-tree distance Array before foliage batching"
    )
    assert "anchor: Vector3 = Vector3(INF, INF, INF)" in foliage
    assert 'row.get("distance_sq", 0.0)' in foliage, (
        "full rebuild must retain the selection-time distance for its canonical anchor"
    )
    assert "base.x - anchor.x" in foliage and "base.z - anchor.z" in foliage, (
        "tree-only refresh must recompute distance from the actual current anchor"
    )
    assert "<= full_detail_radius_sq" in foliage
    assert "TREE_FAR_FOLIAGE_LOBE_INDICES" in foliage


if __name__ == "__main__":
    verify_tree_lod_refresh_avoids_transient_distance_buffer()
    print("OSM_TREE_LOD_DISTANCE_BUFFER_OK")
