from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "brussels_base_ground_surface_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


def test_base_ground_watches_production_node_removal() -> None:
    source = _source()
    assert "tree.node_removed.connect(_on_node_removed)" in source
    assert "tree.node_removed.disconnect(_on_node_removed)" in source
    assert "func _on_node_removed(node: Node) -> void:" in source


def test_ground_removal_releases_material_and_rearms_binding() -> None:
    source = _source()
    handler = _function_body(source, "func _on_node_removed(node: Node) -> void:")
    assert "node != _ground" in handler
    assert "_release_material_ownership()" in handler
    assert "_ready_complete = false" in handler
    assert "_failed = false" in handler
    assert "_awaiting_main = true" in handler
    assert "_start_watching()" in handler
    assert 'call_deferred("_bind_existing_main")' in handler


def test_successful_bind_keeps_scene_replacement_watchers_armed() -> None:
    source = _source()
    finish = _function_body(source, "func _finish_waiting() -> void:")
    assert "node_added.disconnect" not in finish
    assert "node_removed.disconnect" not in finish


def test_runtime_has_symmetric_watcher_helpers() -> None:
    source = _source()
    start = _function_body(source, "func _start_watching() -> void:")
    stop = _function_body(source, "func _stop_watching() -> void:")
    assert "node_added.connect(_on_node_added)" in start
    assert "node_removed.connect(_on_node_removed)" in start
    assert "node_added.disconnect(_on_node_added)" in stop
    assert "node_removed.disconnect(_on_node_removed)" in stop
