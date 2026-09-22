from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    tail = source[start:]
    next_func = tail.find("\nfunc ", len(marker))
    return tail if next_func < 0 else tail[:next_func]


def test_sidewalk_owned_root_never_detaches_synchronously_during_exit_tree() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    exit_block = _function_block(source, "_exit_tree()")
    release_block = _function_block(source, "_release_owned_root()")
    deferred_block = _function_block(source, "_detach_and_free_owned_root(owned_root: Node3D)")

    assert "_tearing_down = true" in exit_block, "teardown state must be entered before releasing the sidewalk root"
    assert "_release_owned_root()" in exit_block, "exit_tree must still release the sidewalk root"

    assert "var owned_root := _root" in release_block, "release must capture the exact owned root before logical ownership is cleared"
    assert 'call_deferred("_detach_and_free_owned_root", owned_root)' in release_block, (
        "owned sidewalk root disposal must leave the SceneTree callback before detach/free"
    )
    assert "_root = null" in release_block, "logical ownership must be cleared immediately"
    assert "remove_child(" not in release_block, "release must never detach synchronously from a SceneTree callback"
    assert "queue_free(" not in release_block, "release must never free synchronously from a SceneTree callback"

    assert "if not is_instance_valid(owned_root):" in deferred_block, "deferred disposal must tolerate an already-freed captured root"
    assert "var parent := owned_root.get_parent()" in deferred_block, "deferred disposal must resolve the captured root's current parent"
    assert "parent.remove_child(owned_root)" in deferred_block, "deferred disposal must detach the captured root, not a later replacement"
    assert "owned_root.queue_free()" in deferred_block, "deferred disposal must queue the captured root for destruction"
