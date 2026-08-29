from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def test_furniture_runtime_uses_event_driven_scene_removal() -> None:
    source = _source()
    assert "tree.node_removed.connect(_on_tree_node_removed)" in source
    assert "tree.node_removed.disconnect(_on_tree_node_removed)" in source
    assert "func _on_tree_node_removed(node: Node) -> void:" in source


def test_scene_replacement_is_not_polled_from_process() -> None:
    source = _source()
    process_body = source.split("func _process(_delta: float) -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert "current_scene" not in process_body
    assert "_reset()" not in process_body


def test_node_removed_path_releases_owned_state_and_rearms_binding() -> None:
    source = _source()
    handler = source.split("func _on_tree_node_removed(node: Node) -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert "node != _scene" in handler
    assert "_reset()" in handler
    assert "_start_watching()" in handler
    assert "call_deferred(\"_try_bind\")" in handler


def test_scene_removal_watcher_stays_armed_after_automatic_bind() -> None:
    source = _source()
    bind_body = source.split("func _bind_scene(scene: Node3D, manual: bool) -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert "_stop_watching()" not in bind_body
