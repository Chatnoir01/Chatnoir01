from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


def test_furniture_runtime_uses_event_driven_scene_removal() -> None:
    source = _source()
    assert "tree.node_removed.connect(_on_tree_node_removed)" in source
    assert "tree.node_removed.disconnect(_on_tree_node_removed)" in source
    assert "func _on_tree_node_removed(node: Node) -> void:" in source


def test_scene_replacement_is_not_polled_from_process() -> None:
    source = _source()
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    assert "current_scene" not in process_body


def test_invalid_scene_fallback_clears_state_and_retries_binding() -> None:
    source = _source()
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    invalid_scene_block = process_body.split("if not is_instance_valid(_scene):", 1)[1].split(
        "\n    if not is_instance_valid(_player):", 1
    )[0]
    assert "_reset()" in invalid_scene_block
    assert "_start_watching()" in invalid_scene_block
    assert 'call_deferred("_try_bind")' in invalid_scene_block


def test_removed_furniture_root_is_rebuilt_while_scene_stays_bound() -> None:
    source = _source()
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    recovery_block = process_body.split("if not is_instance_valid(_player):", 1)[1]
    assert "if not is_instance_valid(_root):" in recovery_block
    root_block = recovery_block.split("if not is_instance_valid(_root):", 1)[1].split(
        "\n    if is_instance_valid(_root) and is_instance_valid(_player):", 1
    )[0]
    assert "_build_once()" in root_block


def test_node_removed_path_releases_owned_state_and_rearms_binding() -> None:
    source = _source()
    handler = _function_body(source, "func _on_tree_node_removed(node: Node) -> void:")
    assert "node != _scene" in handler
    assert "_reset()" in handler
    assert "_start_watching()" in handler
    assert "call_deferred(\"_try_bind\")" in handler


def test_automatic_bind_keeps_scene_removal_watcher_armed() -> None:
    source = _source()
    bind_body = _function_body(source, "func _bind_scene(scene: Node3D, manual: bool) -> void:")
    assert "if manual:" in bind_body
    assert "_stop_watching()" in bind_body
    manual_block = bind_body.split("if manual:", 1)[1].split("\n    else:", 1)[0]
    assert "_stop_watching()" in manual_block
    assert "_start_watching()" not in manual_block
    automatic_block = bind_body.split("\n    else:", 1)[1]
    assert "_start_watching()" in automatic_block
    assert "_stop_watching()" not in automatic_block


def test_manual_bind_disconnects_unused_scene_tree_watchers() -> None:
    source = _source()
    bind_body = _function_body(source, "func _bind_scene(scene: Node3D, manual: bool) -> void:")
    assert "if manual:\n        _stop_watching()\n    else:\n        _start_watching()" in bind_body
