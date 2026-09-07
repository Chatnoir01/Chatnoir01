from pathlib import Path


RUNTIME = Path(__file__).parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_batch_visibility_writes_are_state_guarded() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    assert "var _batches_visible := true" in source

    start = source.index("func _set_batches_visible(enabled: bool) -> void:")
    end = source.index("\nfunc _tree_lod_boundary_crossed", start)
    function = source[start:end]

    # The aggregate state remains authoritative for newly created batches, but
    # existing owned batches must be checked individually so local visibility
    # drift can be repaired. A write is still emitted only for a real child
    # transition, preserving the original no-op write optimization.
    assert "_prune_invalid_owned_batches()" in function
    assert "_batches_visible = enabled" in function
    assert "for batch: MultiMeshInstance3D in _owned_batches:" in function
    assert "if batch.visible != enabled:" in function
    assert "batch.visible = enabled" in function
    assert function.index("if batch.visible != enabled:") < function.index("batch.visible = enabled")
    assert function.count("batch.visible = enabled") == 1

    batch_start = source.index("func _batch(")
    batch_end = source.index("\nfunc _ensure_tree_presentation_meshes", batch_start)
    batch_function = source[batch_start:batch_end]
    assert "instance.visible = _batches_visible" in batch_function
    assert batch_function.index("instance.visible = _batches_visible") < batch_function.index("add_child(instance)")


if __name__ == "__main__":
    verify_batch_visibility_writes_are_state_guarded()
    print("OSM_BATCH_VISIBILITY_CACHE_CONTRACT_OK")
