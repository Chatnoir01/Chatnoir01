from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def section(source: str, start_marker: str, end_marker: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


def verify_tree_foliage_batching_avoids_per_tree_lobe_arrays() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    foliage = section(source, "func _build_tree_foliage_batches(", "\nfunc _build_tree_batches(")

    assert "var lobe_indices" not in foliage, (
        "tree foliage batching must not allocate a transient lobe-index Array for every selected tree"
    )
    assert "lobe_indices.append" not in foliage
    assert "lobe_indices.assign" not in foliage
    assert "for index in range(BrusselsStreetTreeAsset.FOLIAGE_LOBE_COUNT):" in foliage, (
        "near trees must still emit the complete canonical foliage lobe family"
    )
    assert "for index_variant in TREE_FAR_FOLIAGE_LOBE_INDICES:" in foliage, (
        "far trees must still emit exactly the frozen reduced foliage lobe set"
    )
    assert "BrusselsStreetTreeAsset.foliage_lobe_transform(base, osm_id, index)" in foliage
    assert "BrusselsStreetTreeAsset.foliage_is_light(index)" in foliage
    assert "<= full_detail_radius_sq" in foliage


if __name__ == "__main__":
    verify_tree_foliage_batching_avoids_per_tree_lobe_arrays()
    print("OSM_TREE_FOLIAGE_LOBE_ALLOCATION_OK")
