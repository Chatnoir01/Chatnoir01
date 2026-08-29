import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
RUNTIME = ROOT / "game" / "scripts" / "brussels_base_ground_surface_runtime.gd"
CONTRACT = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


def _contract() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


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


def test_node_removed_registry_matches_registered_runtime_sources() -> None:
    contract = _contract()
    declared = []

    for runtime in contract["runtimes"]:
        runtime_source = (ROOT / runtime["path"]).read_text(encoding="utf-8")
        source_uses_node_removed = "node_removed.connect(" in runtime_source
        registry_declares_node_removed = runtime.get("node_removed_cleanup_required") is True

        assert registry_declares_node_removed == source_uses_node_removed, (
            f"{runtime['autoload_name']} node_removed registry/source mismatch"
        )

        if registry_declares_node_removed:
            handler = runtime.get("node_removed_cleanup_handler")
            assert isinstance(handler, str) and handler
            assert f"func {handler}(" in runtime_source
            assert "node_removed.disconnect(" in runtime_source
            declared.append(runtime["autoload_name"])

    assert contract["node_removed_registry_runtime_count"] == len(declared)


def test_base_ground_node_removed_contract_is_explicit() -> None:
    contract = _contract()
    runtime = next(
        item for item in contract["runtimes"]
        if item["autoload_name"] == "BrusselsBaseGroundSurfaceRuntime"
    )
    assert runtime["node_removed_cleanup_required"] is True
    assert runtime["node_removed_cleanup_handler"] == "_on_node_removed"
