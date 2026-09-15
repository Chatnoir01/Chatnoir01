from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.index("\nfunc ", start + 1)
    return source[start:end]


def test_activation_consumer_reconciles_canonical_player_before_reading_position() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in sync_body, (
        "activation consumer must resolve canonical Main/Player ownership itself; "
        "caller-side cache checks are insufficient"
    )

    lookup_index = sync_body.index(canonical_lookup)
    position_index = sync_body.index("global_position")
    assert lookup_index < position_index, (
        "canonical Main/Player ownership must be resolved before activation reads Player coordinates"
    )

    identity_forms = (
        "_player != canonical_player",
        "canonical_player != _player",
        "_player != scene_player",
        "scene_player != _player",
        "_player != current_player",
        "current_player != _player",
    )
    assert any(form in sync_body for form in identity_forms), (
        "activation consumer must reject a valid in-tree cached Player whose identity differs "
        "from the current Main/Player path owner"
    )


def test_activation_consumer_fails_closed_when_canonical_player_path_is_missing() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    lookup_index = sync_body.index(canonical_lookup)
    deactivate_index = sync_body.index("_apply_tree_activation(false)", lookup_index)
    position_index = sync_body.index("global_position")

    null_guards = (
        "not is_instance_valid(canonical_player)",
        "canonical_player == null",
        "not is_instance_valid(scene_player)",
        "scene_player == null",
        "not is_instance_valid(current_player)",
        "current_player == null",
    )
    assert any(guard in sync_body for guard in null_guards), (
        "activation consumer must explicitly fail closed when Main/Player has no canonical owner"
    )
    assert lookup_index < deactivate_index < position_index
