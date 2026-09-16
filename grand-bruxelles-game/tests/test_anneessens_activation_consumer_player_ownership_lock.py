from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_authoritative_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    try:
        end = source.index("\nfunc ", start + 1)
    except ValueError:
        end = len(source)
    return source[start:end]


def test_activation_consumer_reconciles_canonical_player_before_reading_position() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")
    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in sync_body
    lookup_index = sync_body.index(canonical_lookup)
    position_index = sync_body.index("global_position")
    assert lookup_index < position_index
    assert "_player != canonical_player" in sync_body
    assert sync_body.index("_player != canonical_player") < position_index


def test_activation_consumer_fails_closed_when_canonical_player_is_missing_or_detached() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")
    lookup_index = sync_body.index('_scene.get_node_or_null("Player") as Node3D')
    position_index = sync_body.index("global_position")
    null_index = sync_body.index("canonical_player == null")
    live_index = sync_body.index("not canonical_player.is_inside_tree()")
    deactivate_index = sync_body.index("_apply_tree_activation(false)", lookup_index)
    assert lookup_index < null_index < deactivate_index < position_index
    assert lookup_index < live_index < deactivate_index < position_index
    assert "_player = null" in sync_body[lookup_index:deactivate_index]


def test_process_has_no_second_player_coordinate_or_lookup_authority() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    assert 'get_node_or_null("Player")' not in process_body
    assert "global_position" not in process_body
    assert "_sync_build_and_activation()" in process_body


def test_publication_follows_canonical_decision_synchronously() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")
    position_index = sync_body.index("canonical_player.global_position")
    build_index = sync_body.index("_build_once()", position_index)
    assert position_index < build_index
    decision_to_build = sync_body[position_index:build_index]
    assert "await " not in decision_to_build
    assert "call_deferred" not in decision_to_build
    assert "_player =" not in decision_to_build


def test_contract_targets_actual_project_autoload() -> None:
    project = Path("grand-bruxelles-game/project.godot").read_text(encoding="utf-8")
    expected = 'AnneessensOsmFurnitureRuntime="*res://game/scripts/anneessens_osm_furniture_authoritative_runtime.gd"'
    assert expected in project
