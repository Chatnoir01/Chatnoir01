from pathlib import Path


RUNTIME = Path(__file__).parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_batch_visibility_is_transition_cached() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    assert "var _batches_visible := true" in source

    start = source.index("func _set_batches_visible(enabled: bool) -> void:")
    end = source.index("\nfunc _tree_lod_boundary_crossed", start)
    function = source[start:end]

    assert "if _batches_visible == enabled:" in function
    assert "return" in function
    assert "_batches_visible = enabled" in function
    assert function.index("if _batches_visible == enabled:") < function.index("for batch:")
    assert function.count("batch.visible = enabled") == 1

    batch_start = source.index("func _batch(")
    batch_end = source.index("\nfunc _ensure_tree_presentation_meshes", batch_start)
    batch_function = source[batch_start:batch_end]
    assert "instance.visible = _batches_visible" in batch_function
    assert batch_function.index("instance.visible = _batches_visible") < batch_function.index("add_child(instance)")


if __name__ == "__main__":
    verify_batch_visibility_is_transition_cached()
    print("OSM_BATCH_VISIBILITY_CACHE_CONTRACT_OK")
