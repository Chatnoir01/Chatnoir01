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

    assert "_tearing_down = true" in exit_block, "teardown state must be entered before releasing the sidewalk root"
    assert "_release_owned_root()" in exit_block, "exit_tree must still release the sidewalk root"
    assert "_root.queue_free()" in release_block, "owned sidewalk root must remain queued for destruction"
    assert "if parent != null and not _tearing_down:" in release_block, (
        "sidewalk teardown must not call remove_child synchronously while SceneTree is removing the runtime"
    )
    assert "parent.remove_child(_root)" in release_block, (
        "non-teardown rebind/removal must retain immediate detach semantics"
    )
